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
    -- Use vim.fn.system instead of io.popen to avoid blocking
    local version = vim.fn.system("opencode --version 2>/dev/null")
    if vim.v.shell_error ~= 0 then
      version = "unknown"
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

  -- Check port allocation capability
  local port_ok, port_utils = pcall(require, "opencode.port")
  if port_ok then
    local test_port = port_utils.find_free_port()
    if test_port then
      vim.health.ok("Port allocation working (tested port: " .. test_port .. ")")
    else
      vim.health.error("Port allocation failed - cannot bind to TCP socket")
    end
  else
    vim.health.error("Port module not found")
  end

  -- Check server status (uses cached state, non-blocking)
  local ok, server = pcall(require, "opencode.server")
  if ok and server.is_running and server.is_running() then
    local url = server.get_url and server.get_url() or "unknown"
    vim.health.ok("OpenCode server running at " .. url)
  else
    vim.health.info("OpenCode server not running (starts on first use)")
  end
end

return M
