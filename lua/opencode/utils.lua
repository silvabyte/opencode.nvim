---Utility functions for opencode.nvim
local M = {}

---Check if a command exists
---@param cmd string Command name
---@return boolean
function M.has_command(cmd)
  return vim.fn.executable(cmd) == 1
end

---Get project root directory
---@param path? string Starting path (default: current buffer)
---@return string? root Root directory or nil
function M.get_project_root(path)
  path = path or vim.api.nvim_buf_get_name(0)

  -- If empty buffer, use cwd
  if path == "" then
    return vim.fn.getcwd()
  end

  -- Search for markers
  local markers = { ".git", "package.json", "go.mod", "Cargo.toml", ".opencode" }

  local root = vim.fs.find(markers, {
    path = path,
    upward = true,
  })[1]

  if root then
    return vim.fs.dirname(root)
  end

  -- Fallback to cwd
  return vim.fn.getcwd()
end

---Get buffer content
---@param bufnr number Buffer number
---@param start_line? number Start line (0-indexed)
---@param end_line? number End line (0-indexed, exclusive)
---@return string[] lines
function M.get_buffer_lines(bufnr, start_line, end_line)
  start_line = start_line or 0
  end_line = end_line or -1
  return vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
end

---Get cursor position
---@param bufnr? number Buffer number (default: current)
---@return number row, number col (0-indexed)
function M.get_cursor_position(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1] - 1, cursor[2] -- Convert to 0-indexed
end

---Get current line
---@param bufnr? number Buffer number (default: current)
---@return string line
function M.get_current_line(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = M.get_cursor_position(bufnr)
  local lines = M.get_buffer_lines(bufnr, row, row + 1)
  return lines[1] or ""
end

---Get file extension
---@param path string File path
---@return string extension (without dot)
function M.get_extension(path)
  return vim.fn.fnamemodify(path, ":e")
end

---Check if buffer is valid for completion
---@param bufnr number Buffer number
---@return boolean
function M.is_valid_buffer(bufnr)
  -- Check if buffer exists and is loaded
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Check buffer type
  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  if buftype ~= "" and buftype ~= "acwrite" then
    return false
  end

  -- Check if modifiable
  if not vim.api.nvim_buf_get_option(bufnr, "modifiable") then
    return false
  end

  return true
end

---Debounce a function
---@param fn function Function to debounce
---@param delay number Delay in milliseconds
---@return function debounced Debounced function
function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(
      delay,
      0,
      vim.schedule_wrap(function()
        fn(unpack(args))
        timer:close()
        timer = nil
      end)
    )
  end
end

---Throttle a function
---@param fn function Function to throttle
---@param delay number Delay in milliseconds
---@return function throttled Throttled function
function M.throttle(fn, delay)
  local timer = nil
  local last_args = nil

  return function(...)
    last_args = { ... }

    if timer then
      return
    end

    timer = vim.loop.new_timer()
    fn(unpack(last_args))

    timer:start(
      delay,
      0,
      vim.schedule_wrap(function()
        if timer then
          timer:close()
          timer = nil
        end
      end)
    )
  end
end

---Deep copy a table
---@param obj table Table to copy
---@return table copied
function M.deepcopy(obj)
  return vim.deepcopy(obj)
end

---Check if table is empty
---@param t table Table to check
---@return boolean
function M.is_empty(t)
  return next(t) == nil
end

---Merge tables (immutable)
---@param ... table Tables to merge
---@return table merged
function M.merge(...)
  return vim.tbl_deep_extend("force", ...)
end

---Convert table to JSON string
---@param t table Table to encode
---@return string json
function M.encode_json(t)
  -- If table is empty, ensure it encodes as {} not []
  if next(t) == nil then
    return "{}"
  end

  -- Use vim.json.encode if available (Neovim 0.10+), otherwise fallback
  if vim.json and vim.json.encode then
    return vim.json.encode(t)
  else
    return vim.fn.json_encode(t)
  end
end

---Parse JSON string to table
---@param str string JSON string
---@return table? decoded
function M.decode_json(str)
  local ok, result = pcall(vim.fn.json_decode, str)
  if ok then
    return result
  end
  return nil
end

---Log debug message (completely silent, only visible in :messages)
---@param msg string Message
---@param data? table Optional data to log
function M.debug(msg, data)
  if vim.g.opencode_debug then
    local log_msg = "[OpenCode] " .. msg
    if data then
      -- Truncate large data to prevent message overflow
      local data_str = vim.inspect(data)
      if #data_str > 500 then
        data_str = data_str:sub(1, 500) .. "... (truncated)"
      end
      log_msg = log_msg .. " " .. data_str
    end
    -- Silently add to message history using execute (no display, no prompt)
    vim.schedule(function()
      pcall(vim.fn.execute, string.format('echomsg %s', vim.fn.string(log_msg)), 'silent')
    end)
  end
end

---Log info message (non-blocking)
---@param msg string Message
function M.info(msg)
  -- Use echo instead of notify to avoid blocking
  vim.api.nvim_echo({ { "[OpenCode] " .. msg, "Normal" } }, false, {})
end

---Log warning message (non-blocking)
---@param msg string Message
function M.warn(msg)
  vim.schedule(function()
    vim.api.nvim_echo({ { "[OpenCode] " .. msg, "WarningMsg" } }, true, {})
  end)
end

---Log error message (non-blocking)
---@param msg string Message
function M.error(msg)
  vim.schedule(function()
    vim.api.nvim_echo({ { "[OpenCode] " .. msg, "ErrorMsg" } }, true, {})
  end)
end

---Format timestamp
---@param timestamp? number Unix timestamp (default: now)
---@return string formatted
function M.format_timestamp(timestamp)
  timestamp = timestamp or os.time()
  return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

---Sleep for specified milliseconds (async)
---@param ms number Milliseconds
---@param callback function Callback to run after sleep
function M.sleep(ms, callback)
  local timer = vim.loop.new_timer()
  timer:start(ms, 0, vim.schedule_wrap(function()
    timer:close()
    callback()
  end))
end

return M
