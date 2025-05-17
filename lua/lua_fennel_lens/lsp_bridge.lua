local M = {}

local ts = vim.treesitter
local namespace_id = vim.api.nvim_create_namespace("fennel_lsp_bridge")

local function extract_fennel_blocks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local parser = ts.get_parser(bufnr, "lua") or vim.treesitter.languagetree.new(bufnr, "lua")
  local tree = parser:parse()[1]
  local root = tree:root()

  -- Match injections (eval(...) or strings tagged as fennel)
  local q = ts.query.parse("lua", [[
    (function_call
      name: (identifier) @func_name (#eq? @func_name "eval")
      arguments: (arguments
        (string content: (_) @fennel_code)))
  ]])

  local code_blocks = {}

  for _, match in q:iter_matches(root, bufnr, 0, -1) do
    for id, node in pairs(match) do
      local name = q.captures[id]
      if name == "fennel_code" then
        local start_row, start_col, end_row, end_col = node:range()
        local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
        local code = table.concat(lines, "\n")
        table.insert(code_blocks, {
          code = code,
          range = { start_row, end_row},
        })
      end
    end
  end

  return code_blocks
end

local fennel_lsp_client_id = nil

local function send_to_lsp(code_block, original_bufnr)
  local fennel_buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(code_block.code, "\n")
  vim.api.nvim_buf_set_lines(fennel_buf, 0, -1, false, lines)
  vim.bo[fennel_buf].filetype = "fennel" -- required for LSP attach

  local function attach_handler(client_id)
    vim.lsp.buf_attach_client(fennel_buf, client_id)

    -- Manually request diagnostics
    vim.lsp.buf_request(fennel_buf, "textDocument/publishDiagnostics", {
      textDocument = { uri = vim.uri_from_bufnr(fennel_buf) },
    }, function(_, result, ctx, _)
      if result.diagnostics and ctx.bufnr == fennel_buf then
        -- Adjust ranges to map back to original buffer
        for _, d in ipairs(result.diagnostics) do
          d.range.start.line = d.range.start.line + code_block.range[1]
          d.range["end"].line = d.range["end"].line + code_block.range[1]
        end
        vim.diagnostic.set(namespace_id, original_bufnr, result.diagnostics, {})
      end
    end)
  end

  -- Reuse LSP client if already started
  if fennel_lsp_client_id and vim.lsp.get_client_by_id(fennel_lsp_client_id) then
    attach_handler(fennel_lsp_client_id)
  else
    vim.lsp.start({
      name = "fennel_lsp",
      cmd = { "fennel-ls" },
      root_dir = vim.fn.getcwd(),
      on_attach = function(client, _)
        fennel_lsp_client_id = client.id
        attach_handler(client.id)
      end,
    })
  end
end

function M.update()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(namespace_id, bufnr)

  local blocks = extract_fennel_blocks(bufnr)
  for _, block in ipairs(blocks) do
    send_to_lsp(block, bufnr)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufWritePost", "CursorHold" }, {
    pattern = "*.lua",
    callback = function()
      M.update()
    end
  })
end

return M
