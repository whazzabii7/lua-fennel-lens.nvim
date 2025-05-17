local M = {}

local ts = vim.treesitter
local namespace_id = vim.api.nvim_create_namespace("fennel_lsp_bridge")
local fennel_lsp_client_id = nil
local handler_initialized = false
local virtual_buffers = {}

-- Diagnostic handler
local function setup_diagnostic_handler()
  if handler_initialized then return end
  handler_initialized = true

  vim.lsp.handlers["textDocument/publishDiagnostics"] = function(_, result, ctx, _)
    if not result or not result.diagnostics then return end

    local bufnr = vim.uri_to_bufnr(result.uri)
    if not vim.api.nvim_buf_is_loaded(bufnr) then return end

    local diagnostics = result.diagnostics
    local meta = vim.b[bufnr].fennel_lens_meta

    if meta then
      local adjusted = {}
      for _, d in ipairs(diagnostics) do
        if d.range and d.range.start and d.range["end"]
          and d.range.start.line and d.range["end"].line then
          d.range.start.line = d.range.start.line + meta.line_offset
          d.range["end"].line = d.range["end"].line + meta.line_offset
          table.insert(adjusted, d)
        end
      end
      vim.diagnostic.set(namespace_id, meta.original_bufnr, adjusted, {})
    else
      -- Let Lua (and others) handle their diagnostics normally
      vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx)
    end
  end
end

-- Extract embedded fennel blocks
local function extract_fennel_blocks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local parser = ts.get_parser(bufnr, "lua") or vim.treesitter.languagetree.new(bufnr, "lua")
  local tree = parser:parse()[1]
  local root = tree:root()

  local q = ts.query.parse("lua", [[
    (function_call
      name: (dot_index_expression
        table: (identifier) @tbl (#eq? @tbl "fennel")
        field: (identifier) @field (#eq? @field "eval"))
      arguments: (arguments
        (string
          (string_content) @fennel_code)))
  ]])

  local code_blocks = {}

  for _, match in q:iter_matches(root, bufnr, 0, -1) do
    for id, node in pairs(match) do
      local name = q.captures[id]
      if type(node) == "table" and node[1] and type(node[1]) == "userdata" then
        node = node[1]
      end

      if name == "fennel_code" and node then
        local start_row, start_col, end_row, end_col = node:range()
        local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
        local code = table.concat(lines, "\n")
        table.insert(code_blocks, {
          code = code,
          range = { start_row, end_row },
        })
      end
    end
  end

  return code_blocks
end

-- Send code to fennel LSP
local function send_to_lsp(code_block, original_bufnr)
  local key = original_bufnr .. ":" .. code_block.range[1]
  local fennel_buf = virtual_buffers[key]

  if fennel_buf == nil or not vim.api.nvim_buf_is_valid(fennel_buf) then
    fennel_buf = vim.api.nvim_create_buf(false, true)
    virtual_buffers[key] = fennel_buf
  end

  -- Immer aktualisieren, auch wenn Buffer schon existiert
  local lines = vim.split(code_block.code, "\n")
  vim.api.nvim_buf_set_lines(fennel_buf, 0, -1, false, lines)
  vim.bo[fennel_buf].filetype = "fennel"

  -- Setze verständlichen Namen
  local name = "fennel-lens://" .. original_bufnr .. "/" .. code_block.range[1]
  vim.api.nvim_buf_set_name(fennel_buf, name)

  -- Setze Metadaten immer neu
  vim.b[fennel_buf].fennel_lens_meta = {
    original_bufnr = original_bufnr,
    line_offset = code_block.range[1],
  }

  local function attach_handler(client_id)
    vim.lsp.buf_attach_client(fennel_buf, client_id)
  end

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


-- For testing: print extracted fennel blocks
function M.test()
  print(vim.inspect(extract_fennel_blocks(vim.api.nvim_get_current_buf())))
end

-- Main update function
function M.update()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(namespace_id, bufnr)

  local blocks = extract_fennel_blocks(bufnr)
  for _, block in ipairs(blocks) do
    send_to_lsp(block, bufnr)
  end
end

-- Setup autocommands and diagnostic handler
function M.setup()
  setup_diagnostic_handler()

  vim.api.nvim_create_autocmd({ "BufWritePost", "CursorHold" }, {
    pattern = "*.lua",
    callback = function()
      M.update()
    end,
  })
end

return M
