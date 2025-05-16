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

  -- Ensure Treesitter is installed and the query is applied correctly
  local ok, ts_query = pcall(require, "vim.treesitter.query")
  if ok and ts_query then
    -- Retrieve existing queries for Lua injections
    local current_queries = ts_query.get("lua", "injections")

    -- If current_queries is a table, convert it to a string
    local current_queries_str = ""
    if type(current_queries) == "table" then
      current_queries_str = table.concat(current_queries, "\n")
    end

    print(current_queries_str)

    -- Append the custom query for Fennel injection to the existing ones
    local updated_queries = current_queries_str .. "\n" .. fennel_injection

    -- Set the updated queries back to Lua injections
    ts_query.set("lua", "injections", updated_queries)
  else
    print("Error: Treesitter query module is not available or failed to load.")
  end
end

return M
