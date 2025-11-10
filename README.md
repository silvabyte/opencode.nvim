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

```bash
cd /home/matsilva/code/opencode.nvim
./install.sh
```

That's it. Restart Neovim.

## Usage

**Press `<C-]>`** in insert mode → ghost text appears → **press `<Tab>`** to accept.

See [USAGE.md](./USAGE.md) for details.

## Configuration

Optional. Edit `~/.config/nvim/lua/plugins/opencode.lua` to customize:

```lua
require('opencode').setup({
  completion = {
    auto_trigger = true,  -- Auto-complete on typing (default: false)
  },
})
```

See [INSTALL.md](./INSTALL.md) for all options.

## Status

✅ Working. Iterated based on real usage.

## License

MIT
