local M = {}

local ts = vim.treesitter
local virtual_buffers = {}
local namespace_id = vim.api.nvim_create_namespace "fennel_lsp_bridge"
local handler_initialized = false
local original_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
local fennel_lsp_id = nil

local function stable_key(bufnr, block)
  local hash = vim.fn.sha256(block.code)
  return bufnr .. ":" .. hash .. ":" .. block.range.start.line
end

local function clean_diagnostics(raw_diagnostics)
  local diagnostics = {}
  for _, d in pairs(raw_diagnostics) do
    local dia = {
      lnum = d.range.start.line,
      col = d.range.start.character,
      end_lnum = d.range["end"].line,
      end_col = d.range["end"].character,
      severity = d.severity,
      message = d.message,
      code = d.code,
      source = "fennel-ls",
      range = d.range
    }
    table.insert(diagnostics, dia)
  end
  return diagnostics
end

local function setup_diagnostic_handler()
  if handler_initialized then return end
  handler_initialized = true

  vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
    if not result or not result.diagnostics then
      return original_handler(err, result, ctx, config)
    end

    local bufnr = vim.uri_to_bufnr(result.uri)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      return original_handler(err, result, ctx, config)
    end

    local meta = vim.b[bufnr].fennel_lens_meta
    if not meta then
      return original_handler(err, result, ctx, config)
    end

    local adjusted = {}
    local total_lines = vim.api.nvim_buf_line_count(meta.original_bufnr)
    for _, d in ipairs(result.diagnostics) do
      local dcopy = vim.deepcopy(d)

      local ok = dcopy.range and dcopy.range.start and dcopy.range["end"] and
      type(dcopy.range.start.line) == "number" and
      type(dcopy.range["end"].line) == "number"

      if ok then
        local start_line = math.floor(dcopy.range.start.line + meta.line_offset)
        local end_line   = math.floor(dcopy.range["end"].line + meta.line_offset)
        local start_col  = math.floor(dcopy.range.start.character + meta.col_offset)
        local end_col  = math.floor(dcopy.range["end"].character + meta.col_offset)

        if start_line >= 0 and end_line < total_lines then
          dcopy.range.start.line = start_line
          dcopy.range["end"].line = end_line
          dcopy.range.start.character = start_col
          dcopy.range["end"].character = end_col
          table.insert(adjusted, dcopy)
        else
          print("[fennel-lens] Skipping out-of-bounds diag:", start_line, end_line)
        end
      else
        print("[fennel-lens] Invalid diag structure:", vim.inspect(dcopy))
      end
    end

    vim.diagnostic.set(namespace_id, meta.original_bufnr, clean_diagnostics(adjusted), {
      signs = true,
      underline = true,
    })
  end
end

local function ensure_fennel_lsp()
  if fennel_lsp_id and vim.lsp.get_client_by_id(fennel_lsp_id) then
    return fennel_lsp_id
  end

  local client_id = vim.lsp.start_client{
    name = "fennel",
    cmd = { "fennel-ls" },
    root_dir = vim.fn.getcwd(),
    capabilities = vim.lsp.protocol.make_client_capabilities(),
  }

  fennel_lsp_id = client_id
  return client_id
end

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
          range = {
            start = {
              line = start_row,
              character = start_col,
            },
            ["end"] = {
              line = end_row,
              character = end_col,
            },
          },
        })
      end
    end
  end

  return code_blocks
end

local function unsee_buffers()
  for _, v in pairs(virtual_buffers) do
    v.seen = false
  end
end

local function update_virtual_buffers(blocks, original_bufnr)
  for _, block in ipairs(blocks) do
    local key = stable_key(original_bufnr, block)
    local entry = virtual_buffers[key]

    if entry and vim.api.nvim_buf_is_valid(entry.bufnr) then
      -- Update buffer
      vim.api.nvim_buf_set_lines(entry.bufnr, 0, -1, false, vim.split(block.code, "\n"))
      entry.seen = true
    else
      -- Create buffer
      local new_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, vim.split(block.code, "\n"))
      vim.bo[new_buf].filetype = "fennel"

      local name = "fennel-lens://" .. original_bufnr .. "/" .. block.range.start.line .. "-" .. tostring(vim.fn.reltime()[2])
      vim.api.nvim_buf_set_name(new_buf, name)

      -- Start LSP
      local client_id = ensure_fennel_lsp()
      local attached = vim.lsp.buf_attach_client(new_buf, client_id)

      virtual_buffers[key] = {
        bufnr = new_buf,
        seen = true,
      }

      -- Meta + LSP Attach
      vim.b[new_buf].fennel_lens_meta = {
        original_bufnr = original_bufnr,
        line_offset = block.range.start.line,
        col_offset = block.range.start.character,
      }
    end
  end
end

local function clean_buffers()
  for key, v in pairs(virtual_buffers) do
    if not v.seen then
      if vim.api.nvim_buf_is_valid(v.bufnr) then
        vim.api.nvim_buf_delete(v.bufnr, { force = true })
      end
      virtual_buffers[key] = nil
    end
  end
end

-- Main update function
function M.update()
  local bufnr = vim.api.nvim_get_current_buf()
--   vim.diagnostic.reset(namespace_id, bufnr)

  unsee_buffers()
  local blocks = extract_fennel_blocks(bufnr)
  update_virtual_buffers(blocks, bufnr)
  clean_buffers()
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
