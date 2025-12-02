---Port allocation utilities for opencode.nvim
---Enables multiple Neovim instances to run simultaneously without port conflicts
---@class OpenCodePort
local M = {}

---Find an available port by binding to port 0 and letting the OS allocate one
---Uses vim.loop (libuv) which is built into Neovim - no external dependencies
---@return number|nil port The allocated port, or nil on failure
function M.find_free_port()
  local tcp = vim.loop.new_tcp()
  if not tcp then
    return nil
  end

  local ok, _ = tcp:bind("127.0.0.1", 0)
  if not ok then
    tcp:close()
    return nil
  end

  local addr = tcp:getsockname()
  tcp:close()

  if addr and addr.port then
    return addr.port
  end

  return nil
end

---Find a free port with retry logic (synchronous, immediate)
---If the first attempt fails, retry up to max_attempts times
---@param max_attempts? number Maximum attempts (default: 3)
---@return number|nil port The allocated port, or nil on failure
function M.find_free_port_with_retry(max_attempts)
  max_attempts = max_attempts or 3

  for _ = 1, max_attempts do
    local port = M.find_free_port()
    if port then
      return port
    end
    -- No delay - immediate retry since find_free_port is instant
  end

  return nil
end

---Find a free port with retry logic (async version with timer-based delay)
---@param callback function Callback(port: number|nil)
---@param max_attempts? number Maximum attempts (default: 3)
---@param delay_ms? number Delay between retries in ms (default: 10)
function M.find_free_port_with_retry_async(callback, max_attempts, delay_ms)
  max_attempts = max_attempts or 3
  delay_ms = delay_ms or 10

  local attempt = 1

  local function try_find()
    local port = M.find_free_port()
    if port then
      callback(port)
      return
    end

    attempt = attempt + 1
    if attempt <= max_attempts then
      -- using timer instead of vim.sleep since sleep is blocking operation
      local timer = vim.loop.new_timer()
      if timer then
        timer:start(
          delay_ms,
          0,
          vim.schedule_wrap(function()
            timer:close()
            try_find()
          end)
        )
      else
        -- Timer creation failed, give up to avoid potential issues
        callback(nil)
      end
    else
      callback(nil)
    end
  end

  try_find()
end

---Check if a port is available by attempting to bind to it
---@param port number The port to check
---@return boolean available True if port is available
function M.is_port_available(port)
  if not port or port < 1 or port > 65535 then
    return false
  end

  local tcp = vim.loop.new_tcp()
  if not tcp then
    return false
  end

  local ok, _ = tcp:bind("127.0.0.1", port)
  tcp:close()

  return ok == true
end

---Find a free port within a specific range
---@param min_port number Minimum port (inclusive)
---@param max_port number Maximum port (inclusive)
---@return number|nil port The first available port in range, or nil if none found
function M.find_free_port_in_range(min_port, max_port)
  for port = min_port, max_port do
    if M.is_port_available(port) then
      return port
    end
  end
  return nil
end

return M
