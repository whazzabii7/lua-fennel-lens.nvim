local M = {}

-- Neovim API aliases
local api = vim.api

-- Pattern to match `fennel.eval([[...]]`
local function find_fennel_blocks(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}

  for linenr, line in ipairs(lines) do
    local s, e = line:find('fennel%.eval%s*%(%s*%[%[)')
    if s then
      local start_line = linenr - 1
      local block = {}
      linenr = linenr + 1
      while linenr <= #lines and not lines[linenr]:find(']]') do
        table.insert(block, lines[linenr])
        linenr = linenr + 1
      end
      if linenr <= #lines then
        table.insert(block, lines[linenr]:gsub(']]', '')) -- remove closing
      end
      table.insert(blocks, {
        content = table.concat(block, "\n"),
        start_line = start_line,
      })
    end
  end

  return blocks
end

-- Create scratch buffer with Fennel code and attach LSP
local function open_virtual_fennel_buffer(content, origin_buf, line)
  local buf = api.nvim_create_buf(false, true) -- scratch buffer
  api.nvim_buf_set_option(buf, 'filetype', 'fennel')
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, '\n'))
  vim.cmd('vsplit')
  api.nvim_win_set_buf(0, buf)

  -- Optional: Add comment linking back to original buffer
  api.nvim_buf_set_lines(buf, 0, 0, false, {
    string.format('-- from buffer %d, line %d', origin_buf, line + 1),
    ''
  })

  -- You can attach a specific LSP client if needed, e.g.:
  -- local clients = vim.lsp.get_clients({ name = "fennel-ls" })
  -- if clients[1] then
  --   vim.lsp.buf_attach_client(buf, clients[1].id)
  -- end
end

function M.setup()
  vim.api.nvim_create_user_command('FennelExtract', function()
    local bufnr = api.nvim_get_current_buf()
    local blocks = find_fennel_blocks(bufnr)

    if #blocks == 0 then
      print("No fennel.eval blocks found.")
      return
    end

    for _, block in ipairs(blocks) do
      open_virtual_fennel_buffer(block.content, bufnr, block.start_line)
    end
  end, {})
end

return M
