local M = {}

M.check = function()
  vim.health.start("opencode.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim >= 0.9 required")
  end

  -- Check for opencode CLI
  if vim.fn.executable("opencode") == 1 then
    local handle = io.popen("opencode --version 2>/dev/null")
    local version = handle and handle:read("*a") or "unknown"
    if handle then
      handle:close()
    end
    vim.health.ok("opencode CLI found: " .. vim.trim(version))
  else
    vim.health.error("opencode CLI not found", {
      -- TODO: update link to opencode.ai
      "Install: npm install -g @opencode-ai/cli",
      "Or: go install github.com/opencode-ai/opencode@latest",
    })
  end

  -- Check for curl
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl found")
  else
    vim.health.error("curl not found (required for API requests)")
  end

  -- Check for plenary
  local has_plenary = pcall(require, "plenary")
  if has_plenary then
    vim.health.ok("plenary.nvim found")
  else
    vim.health.warn("plenary.nvim not found (optional)")
  end

  -- Check server status
  local ok, server = pcall(require, "opencode.server")
  if ok and server.is_running and server.is_running() then
    vim.health.ok("OpenCode server running")
  else
    vim.health.info("OpenCode server not running (starts on first use)")
  end
end

return M
