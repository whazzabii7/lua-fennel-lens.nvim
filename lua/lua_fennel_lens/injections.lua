-- lua/fennel_lens/injections.lua
local M = {}

function M.setup()
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

  local ok, ts_query = pcall(require, "vim.treesitter.query")
  if ok and ts_query then
    ts_query.set("lua", "injections", fennel_injection)
  end
end

return M
