# conflict.nvim

_A simple NeoVim plugin to resolve merge conflicts with ease._

This plugin was inspired by
[git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim). It began as
a fork but resulted in a complete rewrite focused on a simpler codebase.

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

## ⚙️ Configuration

> [!CAUTION]
> The default mappings start with `c` (e.g., `cc`). This introduces a delay to
> Neovim's built-in **change** operator. Set these to `false` to disable them
> or remap them to your preference.

```lua
require("conflict").setup({
    default_mappings = {
        current = "cc",
        incoming = "ci",
        both = "cb",
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
| :------------------- | :------------------------------------- |
| `:Conflict current`  | Keep the **current** (local) changes   |
| `:Conflict incoming` | Keep the **incoming** (remote) changes |
| `:Conflict both`     | Keep **both** sections                 |
| `:Conflict next`     | Jump to the next conflict              |
| `:Conflict prev`     | Jump to the previous conflict          |
| `:Conflict refresh`  | Manually re-parse the buffer           |

## 🖱️ Mouse Support

When `show_actions` is enabled, you can **left-click** the virtual text labels
directly above a conflict block to resolve it instantly.
