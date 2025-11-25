---OpenCode REST API client
---@class OpenCodeClient
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")
local server = require("opencode.server")

---@type table<string, string> Session pool keyed by project root
local session_pool = {}

---@type table<string, number> Session last used timestamps
local session_last_used = {}

---@type table<string, table> Completion cache keyed by context hash
local completion_cache = {}

---@type number Cache TTL in seconds
local CACHE_TTL = 30

---@type number Max cache entries
local MAX_CACHE_ENTRIES = 50

---@type number|nil Current job ID for cancellation
local current_job_id = nil

---@type number Request ID for deduplication (incremented on each request)
local request_id = 0

---Cancel any in-flight request
function M.cancel()
  if current_job_id then
    pcall(vim.fn.jobstop, current_job_id)
    current_job_id = nil
  end
  -- Bump request ID to invalidate any pending callbacks
  request_id = request_id + 1
end

---Make HTTP request to OpenCode server
---@param method string HTTP method
---@param path string API path
---@param body? table Request body
---@param callback function Callback(success, result)
---@param opts? table Optional request options (timeout, etc.)
function M.request(method, path, body, callback, opts)
  opts = opts or {}
  local url = server.get_url()
  if not url then
    callback(false, "Server not running")
    return
  end

  local full_url = url .. path

  -- Build curl command with timeout (default 30s, configurable via opts)
  local timeout = opts.timeout or 30
  local cmd = { "curl", "-s", "-X", method, "--max-time", tostring(timeout) }

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

  -- Cancel any previous request
  M.cancel()

  -- Capture current request ID for staleness check
  local my_request_id = request_id

  -- Track state for this request
  local stdout_data = {}
  local stderr_data = {}

  local function is_stale()
    return my_request_id ~= request_id
  end

  -- Execute request and track job ID
  current_job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(job_id, code)
      -- Clear job ID if this is the current job
      if current_job_id == job_id then
        current_job_id = nil
      end

      -- Ignore stale responses (request was cancelled or superseded)
      if is_stale() then
        utils.debug("Ignoring stale response", { job_id = job_id })
        return
      end

      -- Process response on exit to ensure we have all data
      if code ~= 0 then
        local err_msg = #stderr_data > 0 and table.concat(stderr_data, "\n")
          or ("Request failed with code " .. code)
        utils.debug("Request failed", { code = code, stderr = err_msg })
        callback(false, err_msg)
        return
      end

      if #stdout_data == 0 then
        utils.debug("Empty response from server")
        callback(false, "Empty response from server")
        return
      end

      local response = table.concat(stdout_data, "\n")

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
  })
end

---Create a new session
---@param project_dir string Project directory
---@param callback function Callback(success, session)
function M.create_session(_, callback)
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

  -- Pass through request options (e.g., timeout)
  local request_opts = {}
  if opts.timeout then
    request_opts.timeout = opts.timeout
  end

  M.request("POST", "/session/" .. session_id .. "/message", body, callback, request_opts)
end

---Generate cache key from context
---@param context table Completion context
---@return string cache_key
function M._get_cache_key(context)
  local key_parts = {
    context.file_path or "",
    tostring(context.cursor_line or 0),
    tostring(context.cursor_col or 0),
    context.current_line or "",
  }
  return table.concat(key_parts, ":")
end

---Check and return cached completion if valid
---@param cache_key string Cache key
---@return table|nil completions Cached completions or nil
function M._get_cached(cache_key)
  local cached = completion_cache[cache_key]
  if cached and (os.time() - cached.timestamp) < CACHE_TTL then
    utils.debug("Cache hit", { key = cache_key })
    return cached.completions
  end
  return nil
end

---Store completion in cache
---@param cache_key string Cache key
---@param completions table Completions to cache
function M._set_cache(cache_key, completions)
  -- Evict old entries if cache is full
  local count = 0
  for _ in pairs(completion_cache) do
    count = count + 1
  end

  if count >= MAX_CACHE_ENTRIES then
    -- Remove oldest entries
    local oldest_key, oldest_time = nil, os.time()
    for key, entry in pairs(completion_cache) do
      if entry.timestamp < oldest_time then
        oldest_key, oldest_time = key, entry.timestamp
      end
    end
    if oldest_key then
      completion_cache[oldest_key] = nil
    end
  end

  completion_cache[cache_key] = {
    completions = completions,
    timestamp = os.time(),
  }
end

---Get or create a pooled session for a project
---@param project_root string Project root directory
---@param callback function Callback(success, session_id)
function M._get_pooled_session(project_root, callback)
  -- Check if we have a valid pooled session
  local existing_session = session_pool[project_root]
  if existing_session then
    session_last_used[project_root] = os.time()
    utils.debug("Reusing pooled session", { id = existing_session })
    callback(true, existing_session)
    return
  end

  -- Create new session and pool it
  M.create_session(project_root, function(success, session)
    if not success then
      callback(false, session)
      return
    end

    local session_id = session.id or session.sessionID or session.session_id
    if not session_id then
      callback(false, "Session ID not found in response")
      return
    end

    -- Pool the session
    session_pool[project_root] = session_id
    session_last_used[project_root] = os.time()
    utils.debug("Created and pooled session", { id = session_id, project = project_root })

    callback(true, session_id)
  end)
end

---Request completion with session pooling and caching
---@param context table Completion context
---@param callback function Callback(success, completions)
function M.get_completion(context, callback)
  -- Check cache first
  local cache_key = M._get_cache_key(context)
  local cached = M._get_cached(cache_key)
  if cached then
    -- Return cached result immediately via vim.schedule for consistent async behavior
    vim.schedule(function()
      callback(true, cached)
    end)
    return
  end

  -- Build completion request
  local prompt = M._build_completion_prompt(context)

  -- Get or create pooled session
  local project_root = context.project_root or utils.get_project_root()

  M._get_pooled_session(project_root, function(success, session_id)
    if not success then
      callback(false, "Failed to get session: " .. tostring(session_id))
      return
    end

    -- Send completion request (don't delete session - it's pooled)
    M.send_message(session_id, prompt, function(msg_success, result)
      if not msg_success then
        -- Session might be stale, invalidate and retry once
        if session_pool[project_root] then
          session_pool[project_root] = nil
          utils.debug("Session stale, retrying with new session")
          M.get_completion(context, callback)
          return
        end
        callback(false, "Failed to get completion: " .. tostring(result))
        return
      end

      -- Parse completion from response
      local completions = M._parse_completion_response(result)

      -- Cache the result
      if completions and #completions > 0 then
        M._set_cache(cache_key, completions)
      end

      callback(true, completions)
    end)
  end)
end

---Clear all pooled sessions
function M.clear_session_pool()
  for _, session_id in pairs(session_pool) do
    M.delete_session(session_id, function() end)
  end
  session_pool = {}
  session_last_used = {}
  utils.debug("Cleared session pool")
end

---Clear completion cache
function M.clear_cache()
  completion_cache = {}
  utils.debug("Cleared completion cache")
end

---Build completion prompt from context
---@param context table Context information
---@return string prompt
function M._build_completion_prompt(context)
  local before_lines = context.content_before or {}
  local after_lines = context.content_after or {}

  -- Use all available context (already truncated by context module)
  local before_text = table.concat(before_lines, "\n")
  local after_text = table.concat(after_lines, "\n")

  local current_line = context.current_line or ""
  local cursor_col = context.cursor_col or 0

  -- Split current line at cursor
  local line_before_cursor = current_line:sub(1, cursor_col)
  local line_after_cursor = current_line:sub(cursor_col + 1)

  -- Build concise, effective prompt
  local prompt_parts = {
    "Complete the code at █. Output ONLY the code to insert, nothing else.",
    "",
    "```" .. (context.language or ""),
  }

  -- Add before context if available
  if before_text ~= "" then
    table.insert(prompt_parts, before_text)
  end

  -- Add current line with cursor marker
  table.insert(prompt_parts, line_before_cursor .. "█" .. line_after_cursor)

  -- Add after context if available
  if after_text ~= "" then
    table.insert(prompt_parts, after_text)
  end

  table.insert(prompt_parts, "```")

  return table.concat(prompt_parts, "\n")
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
      local text = part.text

      -- Strip markdown code fences
      text = text:gsub("^%s*```[%w]*\n?", "") -- Remove opening fence
      text = text:gsub("\n?```%s*$", "") -- Remove closing fence

      -- Clean up whitespace
      text = text:gsub("^%s+", "") -- Leading whitespace
      text = text:gsub("%s+$", "") -- Trailing whitespace

      if text ~= "" then
        table.insert(completions, {
          text = text,
          type = "completion",
        })
      end
    end
  end

  utils.debug("Parsed completions", { count = #completions })
  return completions
end

return M
