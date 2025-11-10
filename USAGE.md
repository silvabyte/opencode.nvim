# Quick Usage Guide

## Basic Workflow

1. **Open a file** in Neovim
2. **Start typing code**
3. **Press `<C-]>`** when you want AI completion
4. **Ghost text appears** in gray at cursor
5. **Press `<Tab>`** to accept, or keep typing to dismiss

## Example Session

```lua
-- Type this in a .lua file:
local function calculate_total(items)
  local sum = 0
  -- Press <C-]> here
```

The AI will suggest something like:
```lua
  for _, item in ipairs(items) do
    sum = sum + item.price
  end
  return sum
```

Press `<Tab>` to accept!

## Keymaps

| Key | Mode | Action |
|-----|------|--------|
| `<C-]>` | Insert | Request completion |
| `<Tab>` | Insert | Accept suggestion |
| `<C-e>` | Insert | Dismiss suggestion |
| `<leader>oc` | Normal | Toggle on/off |
| `<leader>os` | Normal | Show status |

## Commands

| Command | Description |
|---------|-------------|
| `:OpenCodeStart` | Start server |
| `:OpenCodeStop` | Stop server |
| `:OpenCodeStatus` | Check status |
| `:OpenCodeToggle` | Enable/disable |

## Tips & Tricks

### 1. Context Matters
The AI sees ~15 lines before and 5 lines after your cursor. Write meaningful code around where you want completion!

### 2. Be Specific
If you want a specific implementation:
```lua
-- Press <C-]> after writing a comment describing what you want:
-- Create a function that validates email addresses using regex
```

### 3. Manual Trigger
Start with manual trigger (`<C-]>`) to control when AI suggests. Enable auto-trigger later if you like it.

### 4. Multi-line Completions
The AI can complete multiple lines. Press `<Tab>` to accept the whole thing!

### 5. Check Status
If nothing happens, check `:OpenCodeStatus` to ensure server is running.

## Configuration Examples

### Minimal (Manual Trigger)
```lua
require('opencode').setup({})
```

### Auto-Complete (Copilot Style)
```lua
require('opencode').setup({
  completion = {
    auto_trigger = true,
    debounce = 500,  -- Wait 0.5s after typing
  },
})
```

### Custom Keymaps
```lua
require('opencode').setup({})

-- Custom accept key
vim.keymap.set('i', '<C-Space>', function()
  if require('opencode').has_suggestion() then
    require('opencode').accept_suggestion()
  end
end)
```

### Different Model
```lua
require('opencode').setup({
  model = {
    provider = 'anthropic',
    model_id = 'claude-3-5-sonnet-20241022',  -- Different Claude version
  },
})
```

## Troubleshooting

**Q: Nothing happens when I press `<C-]>`**
- Check `:OpenCodeStatus`
- Look at `:messages` for errors
- Ensure OpenCode server is running

**Q: Completions are slow**
- First request is slower (cache warming)
- Check your internet connection
- Verify Anthropic API is responsive

**Q: Wrong suggestions**
- Add more context before cursor
- Try again - AI is non-deterministic
- Write clearer comments describing what you want

**Q: Ghost text not showing**
- Ensure your colorscheme supports `Comment` highlight
- Check if another plugin is clearing virtual text
- Try `:OpenCodeStatus` to verify completion was received

## What to Report

As you use the plugin, note:
- What works well
- What's annoying
- What's missing
- Bugs or crashes

We'll prioritize features based on your real usage!

## Next Steps

After using for a while, consider:
1. Enabling auto-trigger if you like it
2. Adjusting debounce timing
3. Customizing keymaps
4. Requesting new features you need

Happy coding! 🚀
