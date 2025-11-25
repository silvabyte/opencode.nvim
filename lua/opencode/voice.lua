---Voice command integration for opencode.nvim
---Integrates with Audetic VTT to enable voice-triggered AI coding assistance
---@class OpenCodeVoice
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")
local client = require("opencode.client")
local server = require("opencode.server")

---@type string Audetic API base URL
local AUDETIC_URL = "http://127.0.0.1:3737"

---@type string|nil Current job ID from Audetic (used for tracking active recording)
-- selene: allow(unused_variable)
local current_job_id = nil

---@type number|nil Poll timer handle
local poll_timer = nil

---@type number Poll interval in milliseconds
local POLL_INTERVAL = 200

---@type number Max poll attempts (10 seconds)
local MAX_POLL_ATTEMPTS = 50

---@type number Current poll attempt count
local poll_attempts = 0

---@type string Voice state: "idle" | "recording" | "processing" | "executing"
local voice_state = "idle"

---@type number|nil Floating window handle for feedback
local feedback_win = nil

---@type number|nil Floating window buffer
local feedback_buf = nil

---@type number|nil Animation timer for feedback window
local animation_timer = nil

---@type number Animation frame counter
local animation_frame = 0

---@type string[] Animation frames for recording
local recording_frames = { "●", "○" }

---@type string[] Animation frames for processing
local processing_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---Make HTTP request to Audetic API
---@param method string HTTP method
---@param path string API path
---@param callback function Callback(success, result)
local function audetic_request(method, path, callback)
  local full_url = AUDETIC_URL .. path
  local cmd = { "curl", "-s", "-X", method, "--max-time", "5", full_url }

  utils.debug("Audetic request", { method = method, path = path })

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and data[1] and data[1] ~= "" then
        local response = table.concat(data, "\n")
        local decoded = utils.decode_json(response)
        if decoded then
          callback(true, decoded)
        else
          callback(false, "Failed to parse response")
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback(false, "Request failed with code " .. code)
      end
    end,
  })
end

---Create or update the feedback floating window
---@param title string Window title
---@param lines string[] Content lines
---@param hl_group? string Highlight group for the title
local function show_feedback_window(title, lines, hl_group)
  hl_group = hl_group or "Normal"

  -- Calculate dimensions
  local width = 40
  local height = #lines + 2

  -- Ensure minimum dimensions
  width = math.max(width, #title + 4)
  for _, line in ipairs(lines) do
    width = math.max(width, #line + 4)
  end
  width = math.min(width, 60)

  -- Build content with border padding
  local content = { " " .. title, string.rep("─", width - 2) }
  for _, line in ipairs(lines) do
    table.insert(content, " " .. line)
  end

  -- Create buffer if needed
  if not feedback_buf or not vim.api.nvim_buf_is_valid(feedback_buf) then
    feedback_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = feedback_buf })
    vim.api.nvim_set_option_value("filetype", "opencode_voice", { buf = feedback_buf })
  end

  -- Set content
  vim.api.nvim_buf_set_lines(feedback_buf, 0, -1, false, content)

  -- Apply highlighting
  local ns = vim.api.nvim_create_namespace("opencode_voice_hl")
  vim.api.nvim_buf_clear_namespace(feedback_buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(feedback_buf, ns, hl_group, 0, 0, -1)
  vim.api.nvim_buf_add_highlight(feedback_buf, ns, "Comment", 1, 0, -1)

  -- Calculate position (top right)
  local ui = vim.api.nvim_list_uis()[1]
  local row = 1
  local col = ui.width - width - 2

  -- Create or update window
  if not feedback_win or not vim.api.nvim_win_is_valid(feedback_win) then
    feedback_win = vim.api.nvim_open_win(feedback_buf, false, {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      focusable = false,
      zindex = 100,
    })
    -- Set window options
    vim.api.nvim_set_option_value("winblend", 10, { win = feedback_win })
  else
    -- Update existing window
    vim.api.nvim_win_set_config(feedback_win, {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
    })
  end
end

---Close the feedback window
local function close_feedback_window()
  if animation_timer then
    animation_timer:stop()
    animation_timer:close()
    animation_timer = nil
  end

  if feedback_win and vim.api.nvim_win_is_valid(feedback_win) then
    vim.api.nvim_win_close(feedback_win, true)
  end
  feedback_win = nil
  feedback_buf = nil
end

---Start animation for feedback window
---@param state string Current state
local function start_animation(state)
  if animation_timer then
    animation_timer:stop()
    animation_timer:close()
  end

  animation_frame = 0
  animation_timer = vim.loop.new_timer()

  animation_timer:start(
    0,
    150,
    vim.schedule_wrap(function()
      if not feedback_buf or not vim.api.nvim_buf_is_valid(feedback_buf) then
        return
      end

      animation_frame = animation_frame + 1

      local frames, title, hl_group
      if state == "recording" then
        frames = recording_frames
        local frame = frames[(animation_frame % #frames) + 1]
        title = frame .. " Recording..."
        hl_group = "DiagnosticError"
      elseif state == "processing" then
        frames = processing_frames
        local frame = frames[(animation_frame % #frames) + 1]
        title = frame .. " Processing..."
        hl_group = "DiagnosticWarn"
      elseif state == "executing" then
        frames = processing_frames
        local frame = frames[(animation_frame % #frames) + 1]
        title = frame .. " Executing..."
        hl_group = "DiagnosticInfo"
      else
        return
      end

      -- Update just the title line
      local lines = vim.api.nvim_buf_get_lines(feedback_buf, 0, -1, false)
      if #lines > 0 then
        lines[1] = " " .. title
        vim.api.nvim_buf_set_lines(feedback_buf, 0, 1, false, { lines[1] })

        local ns = vim.api.nvim_create_namespace("opencode_voice_hl")
        vim.api.nvim_buf_add_highlight(feedback_buf, ns, hl_group, 0, 0, -1)
      end
    end)
  )
end

---Update voice state and UI
---@param new_state string New state
---@param extra_info? table Additional info to display
local function set_state(new_state, extra_info)
  voice_state = new_state
  extra_info = extra_info or {}

  utils.debug("Voice state changed", { state = new_state, extra = extra_info })

  if new_state == "idle" then
    close_feedback_window()
    vim.g.opencode_voice_status = ""
  elseif new_state == "recording" then
    show_feedback_window(
      "● Recording...",
      { "Speak your command...", "", "Press again to stop" },
      "DiagnosticError"
    )
    start_animation("recording")
    vim.g.opencode_voice_status = "🎤"
  elseif new_state == "processing" then
    show_feedback_window("⠋ Processing...", { "Transcribing audio..." }, "DiagnosticWarn")
    start_animation("processing")
    vim.g.opencode_voice_status = "⏳"
  elseif new_state == "executing" then
    local cmd_text = extra_info.command or "..."
    -- Truncate long commands
    if #cmd_text > 35 then
      cmd_text = cmd_text:sub(1, 32) .. "..."
    end
    show_feedback_window(
      "⠋ Executing...",
      { 'Heard: "' .. cmd_text .. '"', "", "Working on it..." },
      "DiagnosticInfo"
    )
    start_animation("executing")
    vim.g.opencode_voice_status = "🤖"
  end
end

---Stop any active polling
local function stop_polling()
  if poll_timer then
    poll_timer:stop()
    poll_timer:close()
    poll_timer = nil
  end
  poll_attempts = 0
end

---Get the full buffer context for the AI
---@return table context
local function get_buffer_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  return {
    file_path = file_path,
    filetype = filetype,
    content = table.concat(lines, "\n"),
    cursor_line = cursor[1],
    cursor_col = cursor[2],
    total_lines = #lines,
  }
end

---Build the prompt for OpenCode
---@param voice_command string The transcribed voice command
---@param context table Buffer context
---@return string prompt
local function build_prompt(voice_command, context)
  local parts = {
    "Voice command: " .. voice_command,
    "",
    "File: " .. (context.file_path ~= "" and context.file_path or "[unsaved buffer]"),
    "Language: " .. (context.filetype ~= "" and context.filetype or "unknown"),
    "Cursor at line " .. context.cursor_line .. ", column " .. context.cursor_col,
    "",
    "Current file content:",
    "```" .. context.filetype,
    context.content,
    "```",
    "",
    "Execute the voice command on this file. Make the changes directly to the file.",
  }

  return table.concat(parts, "\n")
end

---Execute the voice command via OpenCode
---@param transcription string The transcribed voice command
local function execute_voice_command(transcription)
  set_state("executing", { command = transcription })

  -- Get buffer context
  local context = get_buffer_context()
  local prompt = build_prompt(transcription, context)

  utils.debug("Executing voice command", { command = transcription })

  -- Get project root for session
  local project_root = utils.get_project_root() or vim.fn.getcwd()

  -- Get or create a session and send the command
  client._get_pooled_session(project_root, function(success, session_id)
    if not success then
      utils.error("Failed to get session: " .. tostring(session_id))
      set_state("idle")
      return
    end

    client.send_message(session_id, prompt, {}, function(msg_success, result)
      if not msg_success then
        utils.error("Failed to execute voice command: " .. tostring(result))
        set_state("idle")
        return
      end

      utils.debug("Voice command response", { result = result })

      -- Reload the buffer to pick up any changes made by OpenCode
      vim.schedule(function()
        -- Check if the file was modified externally
        local bufnr = vim.api.nvim_get_current_buf()
        local file_path = vim.api.nvim_buf_get_name(bufnr)

        if file_path ~= "" then
          -- Use checktime to reload if file changed on disk
          vim.cmd("checktime")
        end

        -- Show success feedback briefly
        show_feedback_window(
          "✓ Done!",
          { "Command executed successfully", "", 'Heard: "' .. transcription .. '"' },
          "DiagnosticOk"
        )

        -- Clear after a delay
        vim.defer_fn(function()
          set_state("idle")
        end, 2000)
      end)
    end)
  end)
end

---Poll Audetic status until transcription is ready
---@param _ string The job ID (unused, kept for API consistency)
local function poll_for_transcription(_)
  poll_attempts = poll_attempts + 1

  if poll_attempts > MAX_POLL_ATTEMPTS then
    utils.error("Voice transcription timed out")
    stop_polling()
    set_state("idle")
    return
  end

  audetic_request("GET", "/status", function(success, status)
    if not success then
      utils.debug("Poll failed, retrying...", { attempt = poll_attempts })
      return
    end

    utils.debug("Audetic status", status)

    local phase = status.phase

    if phase == "recording" then
      -- Still recording, keep polling
      set_state("recording")
    elseif phase == "processing" then
      -- Processing, keep polling
      set_state("processing")
    elseif phase == "idle" then
      -- Done! Check for completed job
      stop_polling()

      local last_job = status.last_completed_job
      if last_job and last_job.text and last_job.text ~= "" then
        utils.debug("Got transcription", { text = last_job.text })
        execute_voice_command(last_job.text)
      else
        utils.warn("No transcription received")
        set_state("idle")
      end
    elseif phase == "error" then
      stop_polling()
      utils.error("Recording error: " .. (status.last_error or "unknown"))
      set_state("idle")
    end
  end)
end

---Start polling with a timer
---@param job_id string The job ID to track (stored for potential future use)
local function start_polling(job_id)
  stop_polling()
  current_job_id = job_id -- Store for potential cancellation/reference

  poll_timer = vim.loop.new_timer()
  poll_timer:start(
    POLL_INTERVAL,
    POLL_INTERVAL,
    vim.schedule_wrap(function()
      poll_for_transcription(job_id)
    end)
  )
end

---Toggle voice recording
function M.toggle()
  -- Check if OpenCode server URL is configured (it may still be starting up)
  local server_url = server.get_url()
  if not server_url then
    -- Try to start the server if not running
    utils.info("Starting OpenCode server...")
    server.start()
    -- Give it a moment and retry
    vim.defer_fn(function()
      if server.get_url() then
        M.toggle()
      else
        utils.error("Failed to start OpenCode server. Check :checkhealth opencode")
      end
    end, 2500)
    return
  end

  -- Check if Audetic is available
  audetic_request("GET", "/status", function(success, status)
    if not success then
      utils.error("Audetic is not running. Start it with: audetic")
      return
    end

    local current_phase = status.phase

    if current_phase == "recording" then
      -- Currently recording, stop it
      utils.debug("Stopping recording")
      audetic_request("POST", "/toggle", function(toggle_success, toggle_result)
        if toggle_success then
          utils.debug("Toggle response", toggle_result)
          -- Start polling for the transcription
          local job_id = toggle_result.job_id or status.job_id
          if job_id then
            set_state("processing")
            start_polling(job_id)
          end
        else
          utils.error("Failed to stop recording")
          set_state("idle")
        end
      end)
    elseif current_phase == "idle" then
      -- Not recording, start it
      utils.debug("Starting recording")
      audetic_request("POST", "/toggle", function(toggle_success, toggle_result)
        if toggle_success then
          utils.debug("Toggle response", toggle_result)
          set_state("recording")
          -- Start polling to detect when recording stops
          local job_id = toggle_result.job_id
          if job_id then
            start_polling(job_id)
          else
            -- Poll anyway to detect state changes
            start_polling("pending")
          end
        else
          utils.error("Failed to start recording")
        end
      end)
    elseif current_phase == "processing" then
      utils.info("Already processing a transcription, please wait...")
    end
  end)
end

---Get current voice state
---@return string state
function M.get_state()
  return voice_state
end

---Check if voice is currently active (recording, processing, or executing)
---@return boolean
function M.is_active()
  return voice_state ~= "idle"
end

---Cancel any active voice operation
function M.cancel()
  if voice_state == "recording" then
    -- Try to stop recording
    audetic_request("POST", "/toggle", function() end)
  end

  stop_polling()
  set_state("idle")
  utils.info("Voice command cancelled")
end

---Get statusline component for voice
---@return string
function M.statusline()
  return vim.g.opencode_voice_status or ""
end

---Setup voice commands and keymaps
function M.setup()
  local voice_config = config.get_voice() or {}

  if voice_config.enabled == false then
    return
  end

  -- Create user commands
  vim.api.nvim_create_user_command("OpenCodeVoice", function()
    M.toggle()
  end, { desc = "Toggle OpenCode voice recording" })

  vim.api.nvim_create_user_command("OpenCodeVoiceCancel", function()
    M.cancel()
  end, { desc = "Cancel active voice operation" })

  vim.api.nvim_create_user_command("OpenCodeVoiceStatus", function()
    local state = M.get_state()
    vim.notify("OpenCode Voice: " .. state, vim.log.levels.INFO)
  end, { desc = "Show voice recording status" })

  -- Setup keybind if configured
  local keybind = voice_config.keybind
  if keybind then
    vim.keymap.set(
      "n",
      keybind,
      M.toggle,
      { desc = "Toggle OpenCode voice recording", silent = true }
    )
  end

  utils.debug("Voice module initialized")
end

return M
