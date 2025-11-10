-- Example configurations for opencode.nvim

-- Minimal configuration
require('opencode').setup({})

-- Full configuration with all options
require('opencode').setup({
  server = {
    url = nil,              -- nil = auto-start embedded server
    port = 4096,
    auto_start = true,
    timeout = 30000,
  },

  completion = {
    enabled = true,
    auto_trigger = true,
    trigger_chars = { ".", ":", ">", " " },
    debounce = 300,         -- ms delay before requesting
    max_context_lines = 100,
    show_inline = true,     -- Show as ghost text
    accept_key = '<Tab>',
    dismiss_key = '<C-e>',
  },

  model = {
    provider = 'anthropic',
    model_id = 'claude-sonnet-4-5-20250929',
    temperature = 0.7,
  },

  context = {
    include_imports = true,
    include_recent_files = true,
    use_treesitter = true,
    max_tokens = 8000,
  },

  session = {
    per_project = true,
    persist = true,
    auto_cleanup = true,
  },

  ui = {
    inline_hl_group = 'Comment',
    suggestion_border = 'rounded',
    statusline = true,
  },
})

-- With lazy.nvim
return {
  'opencode/opencode.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'hrsh7th/nvim-cmp',  -- optional
  },
  build = 'cd lsp && npm install',
  config = function()
    require('opencode').setup({
      -- your config here
    })
  end,
}

-- nvim-cmp integration
local cmp = require('cmp')
cmp.setup({
  sources = {
    { name = 'opencode', priority = 1000 },
    { name = 'nvim_lsp' },
    { name = 'buffer' },
  },
})

-- Custom keymaps
vim.keymap.set('i', '<Tab>', function()
  if require('opencode').has_suggestion() then
    require('opencode').accept_suggestion()
    return '<Ignore>'
  else
    return '<Tab>'
  end
end, { expr = true, desc = 'Accept OpenCode suggestion' })

vim.keymap.set('i', '<C-]>', function()
  require('opencode').request_completion()
end, { desc = 'Request OpenCode completion' })

vim.keymap.set('n', '<leader>oc', '<Cmd>OpenCodeToggle<CR>', { desc = 'Toggle OpenCode' })
vim.keymap.set('n', '<leader>os', '<Cmd>OpenCodeStatus<CR>', { desc = 'OpenCode status' })

-- Statusline integration (for lualine)
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('opencode.ui').get_statusline()
      end,
      'encoding',
      'fileformat',
      'filetype',
    },
  },
})
