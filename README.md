# conflict.nvim

_A simple Neovim plugin to resolve merge conflicts with ease._

Its inline conflict UI is similar to the one found in
[VS Code](https://code.visualstudio.com/docs/sourcecontrol/merge-conflicts#_editor-conflict-markers).
The plugin was inspired by
[git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim). It began as
a fork but resulted in a complete rewrite focused on a simpler codebase with the
latest API.

<div align="center">
  <img src="assets/screenshot.png" width="600" alt="conflict.nvim demo">
</div>

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "niekdomi/conflict.nvim",
    opts = {
        -- your configuration here
    }
}
```

## Configuration

The following are the available options with their default values. You can set a
mapping to `false` to disable it.

```lua
require("conflict").setup({
    default_mappings = {
        current = "cc",
        incoming = "ci",
        both = "cb",
        none = false,
        next = "]x",
        prev = "[x",
    },
    show_actions = true,        -- Show clickable [Accept Current | ...] labels
    disable_diagnostics = true, -- Disable LSP/Diagnostics while conflicts exist
    highlights = {
        -- Names of highlight groups to use for sections
        current = "DiffText",
        incoming = "DiffAdd",
    },
})
```

## Commands

| Command              | Description                            |
| -------------------- | -------------------------------------- |
| `:Conflict current`  | Keep the **current** (local) changes   |
| `:Conflict incoming` | Keep the **incoming** (remote) changes |
| `:Conflict both`     | Keep **both** sections                 |
| `:Conflict none`     | Keep **neither** section               |
| `:Conflict next`     | Jump to the next conflict              |
| `:Conflict prev`     | Jump to the previous conflict          |
| `:Conflict refresh`  | Manually re-parse the buffer           |

## Mouse Support

When `show_actions` is enabled, you can **left-click** the virtual text labels
directly above a conflict block to resolve it instantly.
