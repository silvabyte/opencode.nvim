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

---Find a free port with retry logic
---If the first attempt fails, retry up to max_attempts times
---@param max_attempts? number Maximum attempts (default: 3)
---@return number|nil port The allocated port, or nil on failure
function M.find_free_port_with_retry(max_attempts)
  max_attempts = max_attempts or 3

  for attempt = 1, max_attempts do
    local port = M.find_free_port()
    if port then
      return port
    end
    -- Small delay between retries
    if attempt < max_attempts then
      vim.loop.sleep(10)
    end
  end

  return nil
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
