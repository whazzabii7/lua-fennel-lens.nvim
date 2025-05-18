local M = {}

local ts = vim.treesitter
local virtual_buffers = {}
-- local namespace_id = vim.api.nvim_create_namespace("fennel_lsp_bridge")

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

local function update_virtual_buffers(blocks, original_bufnr)
  for _, block in ipairs(blocks) do
    local key = original_bufnr .. ":" .. block.range[1]
    local virt_buf = virtual_buffers[key]

    if not virt_buf or not vim.api.nvim_buf_is_valid(virt_buf) then
      virt_buf = vim.api.nvim_create_buf(false, true)
      virtual_buffers[key] = virt_buf

      -- Set name on create
      local name = "fennel-lens://" .. original_bufnr .. "/" .. block.range[1]
      vim.api.nvim_buf_set_name(virt_buf, name)
    end

    local lines = vim.split(block.code, "\n")
    vim.api.nvim_buf_set_lines(virt_buf, 0, -1, false, lines)
    vim.bo[virt_buf].filetype = "fennel"

    print("Created virtual buffer:", virt_buf, name)
  end
end

-- For testing: print extracted fennel blocks
function M.test()
  print(vim.inspect(extract_fennel_blocks(vim.api.nvim_get_current_buf())))
end

-- Main update function
function M.update()
  local bufnr = vim.api.nvim_get_current_buf()
--   vim.diagnostic.reset(namespace_id, bufnr)

  local blocks = extract_fennel_blocks(bufnr)
  update_virtual_buffers(blocks, bufnr)
end

-- Setup autocommands and diagnostic handler
function M.setup()
  vim.api.nvim_create_autocmd({ "BufWritePost", "CursorHold" }, {
    pattern = "*.lua",
    callback = function()
      M.update()
    end,
  })
end

return M
