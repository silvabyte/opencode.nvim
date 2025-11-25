# opencode.nvim

AI-powered code completion for Neovim.

## Install

Requires [OpenCode](https://github.com/opencode-ai/opencode) and Neovim 0.9+.

**lazy.nvim:**
```lua
{
  "your-username/opencode.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  event = "InsertEnter",
  opts = {},
}
```

## Usage

| Key | Action |
|-----|--------|
| `<C-]>` | Trigger completion |
| `<Tab>` | Accept suggestion |
| `<C-e>` | Dismiss |

## Config

```lua
opts = {
  completion = {
    auto_trigger = true,  -- suggest as you type
    debounce = 150,       -- ms delay
  },
}
```

## Commands

`:OpenCodeToggle` · `:OpenCodeStatus` · `:OpenCodeClearCache`
