-- lua/lua_fennel_lens/init.lua
local M = {}

function M.setup()
  require "lua_fennel_lens.injections".setup()
  require "lua_fennel_lens.lsp_bridge".setup()
end

return M
