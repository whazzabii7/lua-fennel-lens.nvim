-- lua/fennel_lens/injections.lua
local M = {}

function M.setup()
  local fennel_injection = [[
    (
      (function_call
        name: (identifier) @fennel_fn (#eq? @fennel_fn "eval")
        arguments: (arguments
          (string) @fennel_code
        )
      )
      (#set! injection.language "fennel")
      (#set! injection.combined)
    )
  ]]

  ts_query.set("lua", "injections", fennel_injection)
end

return M
