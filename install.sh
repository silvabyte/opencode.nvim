#!/bin/bash
# A very terse setup script for opencode.nvim

set -e

# First ladies and gentlemen, we need to check if OpenCode CLI is installed
if ! command -v opencode &>/dev/null; then
  echo "OpenCode CLI not found. Install it:"
  echo ""
  echo "  npm install -g @opencode-ai/cli"
  echo "  # or"
  echo "  go install github.com/opencode-ai/opencode@latest"
  echo ""
  exit 1
fi

echo "✓ OpenCode CLI found"
echo ""
echo "Add to your lazy.nvim config:"
echo ""
echo '  {'
echo '    "smat/opencode.nvim",'
echo '    dependencies = { "nvim-lua/plenary.nvim" },'
echo '    event = "InsertEnter",'
echo '    opts = {},'
echo '  }'
echo ""
echo "Then run :checkhealth opencode"
