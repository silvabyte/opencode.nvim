# opencode.nvim

AI-powered code completion for Neovim.

## Requirements

- Neovim >= 0.9
- [OpenCode CLI](https://opencode.ai)

## Install

**lazy.nvim**

```lua
-- ~/.config/nvim/lua/plugins/opencode.lua

return {
  "silvabyte/opencode.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  event = "InsertEnter",
  -- Options
  opts = {
    completion = {
      auto_trigger = true,   -- complete as you type
      debounce = 150,        -- ms to wait
      accept_key = "<Tab>",
      dismiss_key = "<C-e>",
      --etc
    },
    model = {
      provider = "anthropic",
      model_id = "claude-sonnet-4-20250514",
      -- or big pickle, big pickle, big pickle!
      -- provider = "opencode",
      -- model_id = "big-pickle"
    },
  }
}
```

Run `:checkhealth opencode` to verify.

## Keys

| Key | Action |
|-----|--------|
| `<C-]>` | Trigger completion |
| `<Tab>` | Accept all |
| `<C-l>` | Accept line |
| `<C-Right>` | Accept word |
| `<C-e>` | Dismiss |

## Commands

`:OpenCodeToggle` · `:OpenCodeStatus` · `:OpenCodeClearCache`
