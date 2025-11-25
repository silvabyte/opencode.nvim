---OpenCode server management
---@class OpenCodeServer
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")

---@type number? Server process handle
local server_handle = nil

---@type number? Server PID
local server_pid = nil

---@type string? Server URL
local server_url = nil

---Start OpenCode server
---@param opts? table Options
---@return boolean success
function M.start(opts)
  opts = opts or {}

  -- Check if already running
  if M.is_running() then
    utils.info("Server already running")
    return true
  end

  local server_config = config.get_server()

  -- If URL is provided, connect to existing server
  if server_config.url then
    server_url = server_config.url
    utils.info("Connecting to server at " .. server_url)
    return M.health_check()
  end

  -- Check if opencode command exists
  if not utils.has_command("opencode") then
    vim.notify(
      "opencode CLI not found. Run :checkhealth opencode for install instructions.",
      vim.log.levels.ERROR
    )
    return false
  end

  -- Start embedded server
  local port = server_config.port or 4096
  local cwd = vim.fn.getcwd()

  utils.debug("Starting OpenCode server", { port = port, cwd = cwd })

  -- Start server process
  local handle, pid
  handle, pid = vim.loop.spawn("opencode", {
    args = { "serve", "--port=" .. port },
    cwd = cwd,
    stdio = { nil, nil, nil },
    detached = true,
  }, function(code, signal)
    utils.debug("Server process exited", { code = code, signal = signal })
    server_handle = nil
    server_pid = nil
    server_url = nil
  end)

  if not handle then
    utils.error("Failed to start server: " .. tostring(pid))
    return false
  end

  server_handle = handle
  server_pid = pid
  server_url = string.format("http://127.0.0.1:%d", port)

  utils.info("Starting OpenCode server on port " .. port)

  -- Wait for server to be ready
  vim.defer_fn(function()
    if M.health_check() then
      utils.info("Server started successfully")
    else
      utils.warn("Server may not be ready yet. Check with :OpenCodeStatus")
    end
  end, 2000)

  return true
end

---Stop OpenCode server
function M.stop()
  if not server_handle then
    utils.debug("No server to stop")
    return
  end

  if server_pid then
    utils.debug("Stopping server", { pid = server_pid })
    vim.loop.kill(server_pid, "sigterm")
  end

  if server_handle then
    server_handle:close()
  end

  server_handle = nil
  server_pid = nil
  server_url = nil

  utils.info("Server stopped")
end

---Check if server is running
---@return boolean
function M.is_running()
  if not server_url then
    return false
  end
  return M.health_check()
end

---Get server URL
---@return string? url
function M.get_url()
  return server_url
end

---Get server PID
---@return number? pid
function M.get_pid()
  return server_pid
end

---Health check server
---@return boolean healthy
function M.health_check()
  if not server_url then
    return false
  end

  -- Try to connect to server with a simple GET request
  local handle = io.popen(string.format('curl -s -f -m 2 "%s/health" 2>/dev/null', server_url))
  if not handle then
    return false
  end

  local result = handle:read("*a")
  handle:close()

  -- If we got any response, consider it healthy
  -- OpenCode might not have a /health endpoint yet, so we're lenient
  if result and #result > 0 then
    return true
  end

  -- Try root endpoint as fallback
  handle = io.popen(string.format('curl -s -f -m 2 "%s/" 2>/dev/null', server_url))
  if not handle then
    return false
  end

  result = handle:read("*a")
  handle:close()

  return result and #result > 0
end

---Get server info
---@return table info
function M.get_info()
  return {
    running = M.is_running(),
    url = server_url,
    pid = server_pid,
  }
end

return M
