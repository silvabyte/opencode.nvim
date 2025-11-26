# opencode.nvim

AI-powered code completion for Neovim.

Problem: Supermaven is dead. They killed it. Those bastards.

Solution: This pile of vibes... but it works! and so can you!

👆The best sales pitch of all time?

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
  -- Use "VeryLazy" if you want voice commands available immediately
  -- Use "InsertEnter" if you only need completions
  event = "VeryLazy",
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

## Voice Commands

Voice-triggered AI coding assistance via [Audetic](https://github.com/silvabyte/audetic) VTT integration.

```lua
opts = {
  voice = {
    enabled = true,
    keybind = "<leader>r",  -- Push-to-talk
  },
}
```

| Key | Action |
|-----|--------|
| `<leader>r` | Start/stop voice recording |

| Command | Action |
|---------|--------|
| `:OpenCodeVoice` | Toggle voice recording |
| `:OpenCodeVoiceCancel` | Cancel active voice operation |
| `:OpenCodeVoiceStatus` | Show voice state |

### How It Works

1. Press `<leader>r` to start recording
2. Speak your command (e.g., "complete this function", "add error handling")
3. Press `<leader>r` again to stop
4. OpenCode executes your command agentically on the current buffer

**Requirements:** [Audetic](https://github.com/silvabyte/audetic) must be running (`audetic` command).
