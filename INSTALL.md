# Installation Guide for Real Usage

## With lazy.nvim (Recommended)

Add to your Neovim config (`~/.config/nvim/lua/plugins/opencode.lua` or in your lazy setup):

```lua
return {
  dir = '/home/matsilva/code/opencode.nvim',  -- Local development path
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('opencode').setup({
      server = {
        auto_start = true,
        port = 4096,
      },
      completion = {
        enabled = true,
        auto_trigger = false,  -- Set true for automatic completions
        debounce = 300,
        max_context_lines = 100,
      },
      model = {
        provider = 'anthropic',
        model_id = 'claude-sonnet-4-5-20250929',
      },
    })
  end,
}
```

## Manual Setup (No Plugin Manager)

Add to your `init.lua`:

```lua
-- Add to runtimepath
vim.opt.runtimepath:append('/home/matsilva/code/opencode.nvim')

-- Load the plugin
require('opencode').setup({
  server = {
    auto_start = true,
    port = 4096,
  },
  completion = {
    enabled = true,
    auto_trigger = false,  -- Manual trigger with <C-]>
    debounce = 300,
  },
  model = {
    provider = 'anthropic',
    model_id = 'claude-sonnet-4-5-20250929',
  },
})
```

## Usage

### Keymaps

- **`<C-]>`** (Insert mode) - Request AI completion
- **`<Tab>`** (Insert mode) - Accept suggestion (if available)
- **`<C-e>`** or **move cursor** - Dismiss suggestion

### Commands

- `:OpenCodeStart` - Start OpenCode server
- `:OpenCodeStop` - Stop server
- `:OpenCodeStatus` - Check server status
- `:OpenCodeToggle` - Enable/disable completions

### Enable Auto-Trigger (Optional)

For Copilot-like automatic completions, set in your config:

```lua
completion = {
  enabled = true,
  auto_trigger = true,  -- Auto-suggest on typing
  debounce = 300,       -- Wait 300ms after typing stops
}
```

## Tips

1. **Start Simple**: Use manual trigger (`<C-]>`) first to get a feel for it
2. **Enable Debug**: Set `vim.g.opencode_debug = true` and check `:messages` if issues arise
3. **Adjust Context**: Increase `max_context_lines` if completions need more context
4. **Try Different Models**: Change `model_id` to experiment with different Claude models

## Troubleshooting

**Completions not working?**
- Check `:OpenCodeStatus` - server should be "Running"
- Verify OpenCode is installed: `opencode --version`
- Check `:messages` for errors

**Server won't start?**
- Make sure port 4096 is available
- Try manual start: `opencode serve --port 4096`

**Slow completions?**
- Reduce `max_context_lines` to 50
- Check your Anthropic API rate limits

## What's Next?

Start using it! We'll add features based on what you actually need:
- Tree-sitter context (smarter code understanding)
- Caching (faster repeated completions)
- Better multi-line handling
- Custom keymaps
- Status line integration

File issues or requests at the GitHub repo as you use it!
