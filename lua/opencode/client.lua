---OpenCode REST API client
---@class OpenCodeClient
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")
local server = require("opencode.server")

---Make HTTP request to OpenCode server
---@param method string HTTP method
---@param path string API path
---@param body? table Request body
---@param callback function Callback(success, result)
function M.request(method, path, body, callback)
  local url = server.get_url()
  if not url then
    callback(false, "Server not running")
    return
  end

  local full_url = url .. path

  -- Build curl command
  local cmd = { "curl", "-s", "-X", method }

  if body then
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    table.insert(cmd, "-d")
    table.insert(cmd, utils.encode_json(body))
  end

  table.insert(cmd, full_url)

  utils.debug("HTTP request", { method = method, path = path, url = full_url })

  -- Execute request
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 then
        callback(false, "Empty response")
        return
      end

      local response = table.concat(data, "\n")
      local decoded = utils.decode_json(response)

      if decoded then
        callback(true, decoded)
      else
        callback(false, "Failed to parse response: " .. response)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        local err = table.concat(data, "\n")
        utils.debug("Request error", { error = err })
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback(false, "Request failed with code: " .. code)
      end
    end,
  })
end

---Create a new session
---@param project_dir string Project directory
---@param callback function Callback(success, session)
function M.create_session(project_dir, callback)
  M.request("POST", "/api/sessions", {
    directory = project_dir,
  }, callback)
end

---Get session by ID
---@param session_id string Session ID
---@param callback function Callback(success, session)
function M.get_session(session_id, callback)
  M.request("GET", "/api/sessions/" .. session_id, nil, callback)
end

---List all sessions
---@param callback function Callback(success, sessions)
function M.list_sessions(callback)
  M.request("GET", "/api/sessions", nil, callback)
end

---Delete session
---@param session_id string Session ID
---@param callback function Callback(success, result)
function M.delete_session(session_id, callback)
  M.request("DELETE", "/api/sessions/" .. session_id, nil, callback)
end

---Send message to session
---@param session_id string Session ID
---@param message string Message content
---@param callback function Callback(success, result)
function M.send_message(session_id, message, callback)
  M.request("POST", "/api/sessions/" .. session_id .. "/messages", {
    content = message,
    role = "user",
  }, callback)
end

---Request completion
---@param context table Completion context
---@param callback function Callback(success, completions)
function M.get_completion(context, callback)
  -- Build completion request
  local prompt = M._build_completion_prompt(context)

  -- Create or get session for this buffer
  local project_root = context.project_root or utils.get_project_root()

  -- For now, create a temporary session for each completion
  -- TODO: Implement session pooling/reuse
  M.create_session(project_root, function(success, session)
    if not success then
      callback(false, "Failed to create session: " .. tostring(session))
      return
    end

    local session_id = session.id

    -- Send completion request
    M.send_message(session_id, prompt, function(msg_success, result)
      -- Clean up session
      M.delete_session(session_id, function() end)

      if not msg_success then
        callback(false, "Failed to get completion: " .. tostring(result))
        return
      end

      -- Parse completion from response
      local completions = M._parse_completion_response(result)
      callback(true, completions)
    end)
  end)
end

---Build completion prompt from context
---@param context table Context information
---@return string prompt
function M._build_completion_prompt(context)
  local lines = {
    "Complete the following code:",
    "",
    "File: " .. (context.file_path or "unknown"),
    "Language: " .. (context.language or "unknown"),
    "",
    "Context before cursor:",
    "```",
  }

  -- Add content before cursor
  if context.content_before then
    vim.list_extend(lines, context.content_before)
  end

  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "Current line: " .. (context.current_line or ""))
  table.insert(lines, "Cursor position: " .. (context.cursor_col or 0))
  table.insert(lines, "")
  table.insert(lines, "Context after cursor:")
  table.insert(lines, "```")

  -- Add content after cursor
  if context.content_after then
    vim.list_extend(lines, context.content_after)
  end

  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "Please provide a completion for the current cursor position.")
  table.insert(lines, "Return only the completion text, no explanations.")

  return table.concat(lines, "\n")
end

---Parse completion response
---@param response table API response
---@return table completions
function M._parse_completion_response(response)
  -- TODO: Implement proper response parsing
  -- For now, return empty array
  return {}
end

return M
