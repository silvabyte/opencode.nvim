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

  -- Always add JSON headers
  table.insert(cmd, "-H")
  table.insert(cmd, "Content-Type: application/json")
  table.insert(cmd, "-H")
  table.insert(cmd, "Accept: application/json")

  if body then
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

      -- Check if response looks like HTML (error page)
      if response:match("^%s*<!") or response:match("<html") then
        utils.error("Received HTML instead of JSON")
        callback(false, "Server returned HTML error page")
        return
      end

      local decoded = utils.decode_json(response)

      if decoded then
        utils.debug("API response", { decoded = decoded })
        callback(true, decoded)
      else
        utils.error("Failed to parse JSON response")
        utils.debug("Raw response", { response = response:sub(1, 500) })
        callback(false, "Failed to parse response: " .. response:sub(1, 200))
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        local err = table.concat(data, "\n")
        if err ~= "" then
          utils.debug("Request stderr", { error = err })
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        utils.warn("Request exited with code: " .. code)
      end
    end,
  })
end

---Create a new session
---@param project_dir string Project directory
---@param callback function Callback(success, session)
function M.create_session(project_dir, callback)
  M.request("POST", "/session", {
    -- Optional: can send empty body or include directory
  }, callback)
end

---Get session by ID
---@param session_id string Session ID
---@param callback function Callback(success, session)
function M.get_session(session_id, callback)
  M.request("GET", "/session/" .. session_id, nil, callback)
end

---List all sessions
---@param callback function Callback(success, sessions)
function M.list_sessions(callback)
  M.request("GET", "/session", nil, callback)
end

---Delete session
---@param session_id string Session ID
---@param callback function Callback(success, result)
function M.delete_session(session_id, callback)
  M.request("DELETE", "/session/" .. session_id, nil, callback)
end

---Send message to session
---@param session_id string Session ID
---@param message string Message content
---@param opts? table Optional parameters (model, agent, etc.)
---@param callback function Callback(success, result)
function M.send_message(session_id, message, opts, callback)
  -- Handle optional opts parameter
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}

  -- Get model configuration
  local model_config = config.get_model()

  local body = {
    parts = {
      {
        type = "text",
        text = message,
      },
    },
  }

  -- Add model configuration if provided
  if model_config and model_config.provider and model_config.model_id then
    body.model = {
      providerID = model_config.provider,
      modelID = model_config.model_id,
    }
    utils.debug("Using model", { provider = model_config.provider, model = model_config.model_id })
  end

  M.request("POST", "/session/" .. session_id .. "/message", body, callback)
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

    -- Debug: check session structure
    utils.debug("Session created", { session = session })

    -- Extract session ID (handle different response structures)
    local session_id = session.id or session.sessionID or session.session_id
    if not session_id then
      utils.error("Session created but no ID found in response")
      utils.debug("Session object", { session = session })
      callback(false, "Session ID not found in response")
      return
    end

    utils.debug("Using session", { id = session_id })

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
  -- Keep prompt very short to avoid context overflow
  local before_lines = context.content_before or {}
  local after_lines = context.content_after or {}

  -- Only take last 10 lines before and 5 lines after
  local before_start = math.max(1, #before_lines - 10)
  local before_text = table.concat(vim.list_slice(before_lines, before_start), "\n")
  local after_text = table.concat(vim.list_slice(after_lines, 1, 5), "\n")

  local lines = {
    "Complete the code at cursor position:",
    "",
    "```" .. (context.language or ""),
    before_text,
    "⎕ <-- cursor here",
    after_text,
    "```",
    "",
    "Provide a brief code completion (one line or short snippet). No explanations.",
  }

  return table.concat(lines, "\n")
end

---Parse completion response
---@param response table API response
---@return table completions
function M._parse_completion_response(response)
  -- Response format: { info: {...}, parts: [{type, text, ...}, ...] }
  if not response or not response.parts then
    utils.debug("No parts in response", { response = response })
    return {}
  end

  local completions = {}

  -- Extract text from all text parts
  for _, part in ipairs(response.parts) do
    if part.type == "text" and part.text then
      -- For now, treat the entire response as one completion
      -- In Phase 2, we'll do smarter parsing
      table.insert(completions, {
        text = part.text,
        type = "completion",
      })
    end
  end

  utils.debug("Parsed completions", { count = #completions })
  return completions
end

return M
