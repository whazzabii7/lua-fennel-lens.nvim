-- lua/fennel_lens/injections.lua
local M = {}

local function get_query_source(lang, query_type)
  local files = vim.treesitter.query.get_files(lang, query_type)
  local combined = {}
  for _, file in ipairs(files) do
    local lines = vim.fn.readfile(file)
    vim.list_extend(combined, lines)
  end
  return table.concat(combined, "\n")
end

function M.setup()
  local base = get_query_source("lua", "injections")
  local fennel_injection = [[
    ((function_call
      name: [
        (identifier) @_fennel_identifier
        (_
          _
          (identifier) @_fennel_identifier)
      ]
      arguments: (arguments
        (string
          content: _ @injection.content)))
      (#set! injection.language "fennel")
      (#eq? @_fennel_identifier "eval"))
  ]]

  vim.treesitter.query.set("lua", "injections", base.."\n"..fennel_injection)
end

return M
