#!/bin/bash
# opencode.nvim installer

set -e

echo "🚀 Installing opencode.nvim..."

# Check if opencode is installed
if ! command -v opencode &>/dev/null; then
  echo "❌ OpenCode not found. Install it first:"
  echo "   npm install -g @opencode-ai/cli"
  exit 1
fi

# Detect Neovim config location
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

if [ ! -d "$NVIM_CONFIG" ]; then
  echo "❌ Neovim config not found at $NVIM_CONFIG"
  exit 1
fi

# Check for lazy.nvim
LAZY_DIR="$NVIM_CONFIG/lua/plugins"
if [ -d "$LAZY_DIR" ]; then
  echo "📦 Detected lazy.nvim"

  cat >"$LAZY_DIR/opencode.lua" <<EOF
return {
  dir = '$(pwd)',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  lazy = true,
  event = 'InsertEnter',
  config = function()
    local ok, opencode = pcall(require, 'opencode')
    if ok then
      opencode.setup({
        completion = {
          auto_trigger = false,  -- Use <C-]> to trigger
        },
      })
    end
  end,
}
EOF

  echo "✅ Created $LAZY_DIR/opencode.lua"
  echo "   Restart Neovim and run :Lazy sync"
else
  echo "📝 Manual setup required"
  echo ""
  echo "Add to your init.lua:"
  echo ""
  echo "  vim.opt.runtimepath:append('$(pwd)')"
  echo "  require('opencode').setup({})"
  echo ""
fi

echo ""
echo "🎯 Usage:"
echo "   <C-]>  Request completion (insert mode)"
echo "   <Tab>  Accept suggestion"
echo ""
echo "✨ Done! Check USAGE.md for more"
