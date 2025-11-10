# opencode.nvim

AI-powered autocompletion plugin for Neovim using [OpenCode](https://github.com/opencode-ai/opencode).

## Features

- 🤖 AI-powered code completions using OpenCode's SDK
- 🔌 Multi-provider support (Anthropic, OpenAI, Google, local models)
- 🌳 Smart context extraction with Tree-sitter
- 💬 Inline ghost text (like GitHub Copilot)
- 🎯 File system-aware completions
- 🔄 Session management per project
- ⚡ Async, non-blocking completions
- 🎨 Highly configurable

## Requirements

- Neovim >= 0.9.0
- [OpenCode](https://github.com/opencode-ai/opencode) installed
- Node.js >= 18 (for LSP server, optional)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) (optional, for completion UI)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'opencode/opencode.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'hrsh7th/nvim-cmp',  -- optional
  },
  build = 'cd lsp && npm install',  -- For LSP server
  config = function()
    require('opencode').setup({
      -- Your configuration here
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'opencode/opencode.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
  run = 'cd lsp && npm install',
  config = function()
    require('opencode').setup()
  end,
}
```

## Quick Start

```lua
require('opencode').setup({
  server = {
    auto_start = true,
    port = 4096,
  },
  completion = {
    enabled = true,
    auto_trigger = true,
    debounce = 300,
  },
  model = {
    provider = 'anthropic',
    model_id = 'claude-sonnet-4-5-20250929',
  },
})
```

## Usage

### Commands

- `:OpenCodeStart` - Start OpenCode server
- `:OpenCodeStop` - Stop OpenCode server
- `:OpenCodeStatus` - Show server status
- `:OpenCodeToggle` - Toggle completion
- `:OpenCodeSessionNew` - Create new session
- `:OpenCodeSessionList` - List sessions

### Keymaps

Default keymaps (can be customized):

```lua
-- Insert mode
<Tab>     -- Accept suggestion (if available)
<C-]>     -- Request completion manually

-- Normal mode
<leader>oc  -- Toggle OpenCode
<leader>os  -- Show status
```

## Configuration

Full configuration options:

```lua
require('opencode').setup({
  -- Server configuration
  server = {
    url = nil,              -- nil = auto-start embedded server
    port = 4096,
    auto_start = true,
    timeout = 30000,
  },

  -- Completion settings
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

  -- Model configuration
  model = {
    provider = 'anthropic',
    model_id = 'claude-sonnet-4-5-20250929',
    temperature = 0.7,
  },

  -- Context settings
  context = {
    include_imports = true,
    include_recent_files = true,
    use_treesitter = true,
    max_tokens = 8000,
  },

  -- Session settings
  session = {
    per_project = true,     -- One session per project
    persist = true,         -- Save sessions
    auto_cleanup = true,
  },

  -- UI settings
  ui = {
    inline_hl_group = 'Comment',
    suggestion_border = 'rounded',
    statusline = true,
  },
})
```

## Architecture

opencode.nvim uses a hybrid architecture:

1. **Custom nvim-cmp source** for inline completions
2. **Optional LSP server** for additional features (hover, diagnostics)
3. **OpenCode SDK** for AI capabilities and file system access

```
┌─────────────────┐
│  Neovim Buffer  │
└────────┬────────┘
         │
         ├─→ nvim-cmp source
         │   └─→ lua/opencode/completion.lua
         │
         └─→ LSP (optional)
             └─→ lsp/opencode-lsp.ts

Both connect to:
         ▼
┌─────────────────────┐
│  OpenCode Server    │
│  (REST API)         │
└─────────────────────┘
```

## Development Status

🚧 **Under active development** 🚧

Current phase: **Phase 1 - Foundation (MVP)**

- [x] Project scaffolding
- [ ] Server management
- [ ] Basic REST client
- [ ] Simple completion source
- [ ] Configuration system
- [ ] User commands

See [TODO.md](./TODO.md) for full roadmap.

## Contributing

Contributions welcome! Please read our [Contributing Guide](./CONTRIBUTING.md) first.

## License

MIT License - see [LICENSE](./LICENSE)

## Credits

Built with ❤️ for [OpenCode](https://github.com/opencode-ai/opencode) users.

Inspired by:
- [GitHub Copilot](https://github.com/features/copilot)
- [augment.vim](https://github.com/augmentcode/augment.vim)
- [cmp-ai](https://github.com/tzachar/cmp-ai)
