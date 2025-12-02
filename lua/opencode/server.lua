---OpenCode server management
---@class OpenCodeServer
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")
local port_utils = require("opencode.port")

---@type number? Server process handle
local server_handle = nil

---@type number? Server PID
local server_pid = nil

---@type string? Server URL
local server_url = nil

---@type boolean Cached server health state
local server_healthy = false

---@type uv_timer_t? Periodic health check timer
local health_check_timer = nil

---@type boolean Whether a health check is currently in progress
local health_check_in_progress = false

-- Health check interval in milliseconds (30 seconds)
local HEALTH_CHECK_INTERVAL = 30000

-- Forward declarations for local functions
local start_health_timer
local stop_health_timer

---Start OpenCode server
---@param opts? table Options
---@return boolean success
function M.start(opts)
  opts = opts or {}

  -- Check if already running (uses cached state, non-blocking)
  if server_url and server_healthy then
    utils.info("Server already running")
    return true
  end

  local server_config = config.get_server()

  -- If URL is provided, connect to existing server
  if server_config.url then
    server_url = server_config.url
    utils.info("Connecting to server at " .. server_url)
    -- Perform async health check to validate connection
    M.health_check_async(function(healthy)
      if healthy then
        utils.info("Connected to server at " .. server_url)
        start_health_timer()
      else
        utils.warn("Server at " .. server_url .. " is not responding")
      end
    end)
    return true -- Return immediately, health check is async
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
  -- Use configured port, or dynamically allocate a free one
  local port = server_config.port
  if not port then
    port = port_utils.find_free_port()
    if not port then
      utils.error("Failed to allocate a free port for OpenCode server")
      return false
    end
    utils.debug("Dynamically allocated port", { port = port })
  end

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
    server_healthy = false
    stop_health_timer()
  end)

  if not handle then
    utils.error("Failed to start server: " .. tostring(pid))
    return false
  end

  server_handle = handle
  server_pid = pid
  server_url = string.format("http://127.0.0.1:%d", port)

  utils.info("Starting OpenCode server on port " .. port)

  -- Wait for server to be ready, then perform async health check
  vim.defer_fn(function()
    M.health_check_async(function(healthy)
      if healthy then
        local model_config = config.get_model()
        local model_info = model_config.model_id or "unknown"
        utils.info("Server started successfully (model: " .. model_info .. ")")
        start_health_timer()
      else
        utils.warn("Server may not be ready yet. Check with :OpenCodeStatus")
      end
    end)
  end, 2000)

  return true
end

---Stop OpenCode server
function M.stop()
  -- Stop health check timer first
  stop_health_timer()

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
  server_healthy = false

  utils.info("Server stopped")
end

---Check if server is running (returns cached state, non-blocking)
---@return boolean
function M.is_running()
  if not server_url then
    return false
  end
  return server_healthy
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

---Perform async health check on server
---@param callback function Callback(healthy: boolean)
function M.health_check_async(callback)
  if not server_url then
    server_healthy = false
    callback(false)
    return
  end

  if health_check_in_progress then
    -- Return cached state if check already in progress
    callback(server_healthy)
    return
  end

  health_check_in_progress = true

  -- Try /health endpoint first
  utils.async_curl({ "-f", server_url .. "/health" }, function(success, _)
    if success then
      server_healthy = true
      health_check_in_progress = false
      callback(true)
      return
    end

    -- Fallback to root endpoint
    utils.async_curl({ "-f", server_url .. "/" }, function(root_success, _)
      server_healthy = root_success
      health_check_in_progress = false
      callback(root_success)
    end, { timeout = 2 })
  end, { timeout = 2 })
end

---Refresh server status asynchronously
---@param callback? function Callback(healthy: boolean)
function M.refresh_status(callback)
  M.health_check_async(function(healthy)
    if callback then
      callback(healthy)
    end
  end)
end

---Start periodic health check timer
start_health_timer = function()
  if health_check_timer then
    return -- Already running
  end

  health_check_timer = vim.loop.new_timer()
  if not health_check_timer then
    utils.debug("Failed to create health check timer")
    return
  end

  health_check_timer:start(
    HEALTH_CHECK_INTERVAL,
    HEALTH_CHECK_INTERVAL,
    vim.schedule_wrap(function()
      M.health_check_async(function(healthy)
        utils.debug("Periodic health check", { healthy = healthy })
      end)
    end)
  )
end

---Stop periodic health check timer
stop_health_timer = function()
  if health_check_timer then
    health_check_timer:stop()
    health_check_timer:close()
    health_check_timer = nil
  end
end

---Get server info
---@return table info
function M.get_info()
  return {
    running = M.is_running(),
    url = server_url,
    pid = server_pid,
    healthy = server_healthy,
  }
end

---Check if server is healthy (alias for is_running, returns cached state)
---@return boolean
function M.is_healthy()
  return server_healthy
end

return M
