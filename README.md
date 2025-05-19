# lua-fennel-lens.nvim

**lua-fennel-lens.nvim** adds syntax highlighting and (optional) LSP support for embedded Fennel code inside Lua files. It specifically targets use cases where Fennel is evaluated inline via `fennel.eval(...)`, allowing you to write and maintain hybrid Lua/Fennel code with better developer tooling in Neovim.

## TODOs

There are still some clean up to do:
- make code cleaner
- lua LSP don't "sees" the definition of fennel funktions, so you still get undefined global warning
- make features optional (both syntax highlighting and LSP bridge, so you can use what you need)
- maybe I will add a "translation" for documentation trigger, so vim.lsp.buf.hover() sends infos from virtual buffer to main buffer.

## Features

- Treesitter-based syntax highlighting for Fennel code inside `fennel.eval(...)` strings.
- Optional LSP support for embedded Fennel code.
- No configuration required for basic highlighting.
- Designed for performance and extensibility.

## Motivation

Fennel is often embedded inside Lua using `fennel.eval`. However, most tools do not recognize or highlight this inline code properly. This plugin acts like a "lens" that reveals the structure and meaning of embedded Fennel, similar to how `ffi.cdef` enables embedded C in Lua.

## Installation

Use your favorite plugin manager:

### lazy.nvim

```lua
{
  "whazzabii7/lua-fennel-lens.nvim",
  config = function()
    require("lua_fennel_lens").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "whazzabii7/lua-fennel-lens.nvim",
  config = function()
    require("fennel_lens").setup()
  end,
})
```

## Usage

Out of the box, `fennel-lens.nvim` will:

- Add Treesitter injection rules for Lua files.
- Highlight Fennel code inside `fennel.eval("...")` string calls.

Example:

```lua
local fennel = require("fennel")

fennel.eval([[
(fn greet [name]
  (print (.. "Hello, " name "!")))
]])
```

The body of the `fennel.eval` call will now be syntax-highlighted as Fennel.

## LSP Support (Experimental)

This version of this plugin supports inline LSP features for Fennel code, by extracting the content into virtual buffers and attaching a Fennel language server.

This functionality will be opt-in and focused on performance and minimal distraction.

## Requirements

- Neovim 0.9 or higher
- nvim-treesitter
- Optional: Fennel LSP (e.g., fennel-ls)

## License

MIT

## Contributing

Contributions are welcome. Feel free to open issues or submit pull requests to improve highlighting, add LSP support, or expand language detection.
