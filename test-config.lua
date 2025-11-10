-- Test configuration for opencode.nvim
-- Load this file in Neovim to test the plugin locally
-- Usage: nvim -u test-config.lua

-- Set runtime path to include this plugin
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Minimal plugin setup for testing
-- (In real usage, use a plugin manager)
vim.cmd([[
  filetype plugin indent on
  syntax enable
]])

-- Load the plugin
require('opencode').setup({
  server = {
    auto_start = true,
    port = 4096,
  },
  completion = {
    enabled = true,
    auto_trigger = false,  -- Set to false for manual testing
    debounce = 300,
  },
  model = {
    provider = 'anthropic',
    model_id = 'claude-sonnet-4-5-20250929',
  },
})

-- Disable debug mode for smooth UX (re-enable to see detailed logs in :messages)
vim.g.opencode_debug = false

-- Show status on startup
vim.defer_fn(function()
  print(require('opencode').status())
end, 1000)

-- Helpful test commands
print("OpenCode test environment loaded!")
print("Commands:")
print("  :OpenCodeStatus - Check server status")
print("  :OpenCodeStart - Start server")
print("  :OpenCodeStop - Stop server")
print("")
print("Keymaps:")
print("  <C-]> (insert mode) - Request completion")
print("  <leader>oc - Toggle OpenCode")
print("  <leader>os - Show status")
