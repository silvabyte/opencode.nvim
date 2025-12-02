---@class OpenCode
---@field config OpenCodeConfig
---@field server OpenCodeServer
---@field client OpenCodeClient
---@field completion OpenCodeCompletion
local M = {}

-- Default configuration optimized for snappy experience
local default_config = {
  server = {
    url = nil,
    port = nil, -- nil = auto-allocate free port (enables multiple Neovim instances)
    auto_start = true,
    timeout = 15000, -- Reduced timeout for faster failure detection
  },
  completion = {
    enabled = true,
    auto_trigger = true,
    trigger_chars = { ".", ":", "(", " ", "\t" },
    debounce = 150, -- Reduced from 300ms for snappier feel
    max_context_lines = 100,
    show_inline = true,
    accept_key = "<Tab>",
    dismiss_key = "<C-e>",
  },
  model = {
    provider = "opencode",
    model_id = "big-pickle",
    temperature = 0.3, -- Lower temperature for more consistent completions
  },
  context = {
    include_imports = true,
    include_recent_files = false, -- Disabled for speed
    use_treesitter = true,
    max_tokens = 4000, -- Reduced for faster responses
  },
  session = {
    per_project = true,
    persist = true,
    auto_cleanup = true,
  },
  ui = {
    inline_hl_group = "Comment",
    suggestion_border = "rounded",
    statusline = true,
    loading_indicator = "eol", -- "eol" (end of line), "statusline", "none"
    loading_delay = 100, -- ms delay before showing loading indicator (avoids flicker)
  },
  voice = {
    enabled = true,
    keybind = "<leader>r", -- Push-to-talk keybind
  },
}

---Setup opencode.nvim
---@param opts? OpenCodeConfig User configuration (all fields optional, merged with defaults)
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})

  -- Load modules
  local ok, config_module = pcall(require, "opencode.config")
  if not ok then
    vim.notify("Failed to load opencode.config: " .. config_module, vim.log.levels.ERROR)
    return
  end

  -- Initialize configuration
  config_module.setup(M.config)

  -- Load server module
  local server_ok, server_module = pcall(require, "opencode.server")
  if server_ok then
    M.server = server_module
  end

  -- Load client module
  local client_ok, client_module = pcall(require, "opencode.client")
  if client_ok then
    M.client = client_module
  end

  -- Load completion module
  local completion_ok, completion_module = pcall(require, "opencode.completion")
  if completion_ok then
    M.completion = completion_module
    -- Setup completion autocmds
    completion_module.setup_autocmds()
  end

  -- Load session module
  local session_ok, session_module = pcall(require, "opencode.session")
  if session_ok then
    M.session = session_module
  end

  -- Load UI module and setup highlights
  local ui_ok, ui_module = pcall(require, "opencode.ui")
  if ui_ok and ui_module.setup_highlights then
    ui_module.setup_highlights()
  end

  -- Load voice module
  local voice_ok, voice_module = pcall(require, "opencode.voice")
  if voice_ok then
    M.voice = voice_module
    voice_module.setup()
  end

  -- Auto-start server if configured
  if M.config.server.auto_start and M.server then
    vim.defer_fn(function()
      M.server.start()
    end, 100)
  end

  -- Setup autocommands
  M._setup_autocommands()

  -- Silent initialization (only show in debug mode)
  if vim.g.opencode_debug then
    vim.notify("opencode.nvim initialized", vim.log.levels.INFO)
  end
end

---Setup autocommands
function M._setup_autocommands()
  local group = vim.api.nvim_create_augroup("OpenCode", { clear = true })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      -- Clear pooled sessions
      if M.client and M.client.clear_session_pool then
        M.client.clear_session_pool()
      end

      -- Stop server
      if M.server and M.server.stop then
        M.server.stop()
      end
    end,
  })

  -- Session cleanup
  if M.config.session.auto_cleanup then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        if M.session and M.session.cleanup_sessions then
          M.session.cleanup_sessions()
        end
      end,
    })
  end
end

---Get current configuration
---@return OpenCodeConfig
function M.get_config()
  return M.config
end

---Check if OpenCode is available (returns cached state, non-blocking)
---@return boolean
function M.is_available()
  if not M.server then
    return false
  end
  return M.server.is_running()
end

---Check if OpenCode is available with fresh status (async)
---@param callback function Callback(available: boolean)
function M.is_available_async(callback)
  if not M.server then
    callback(false)
    return
  end
  M.server.refresh_status(callback)
end

---Toggle completion on/off
function M.toggle()
  if not M.config then
    vim.notify("OpenCode not initialized. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  M.config.completion.enabled = not M.config.completion.enabled
  local status = M.config.completion.enabled and "enabled" or "disabled"
  vim.notify("OpenCode completion " .. status, vim.log.levels.INFO)
end

---Get server status (returns cached state for immediate display)
---@return string
function M.status()
  if not M.server then
    return "Server module not loaded"
  end

  local running = M.server.is_running()
  local status_str = running and "Running" or "Stopped"

  if running then
    local url = M.server.get_url()
    return string.format("OpenCode Server: %s (%s)", status_str, url)
  else
    return string.format("OpenCode Server: %s", status_str)
  end
end

---Get server status with fresh check (async)
---Shows "Checking..." immediately, then updates with fresh state
---@param callback? function Optional callback(status_string: string)
function M.status_async(callback)
  if not M.server then
    local msg = "Server module not loaded"
    if callback then
      callback(msg)
    end
    return
  end

  -- Show immediate cached status
  local cached_status = M.status()
  local url = M.server.get_url()

  -- If we have a URL, show "Checking..." and refresh
  if url then
    vim.api.nvim_echo({ { "OpenCode Server: Checking...", "Normal" } }, false, {})

    M.server.refresh_status(function(healthy)
      local status_str = healthy and "Running" or "Stopped"
      local final_msg
      if healthy then
        final_msg = string.format("OpenCode Server: %s (%s)", status_str, url)
      else
        final_msg = string.format("OpenCode Server: %s", status_str)
      end

      vim.api.nvim_echo({ { final_msg, "Normal" } }, false, {})

      if callback then
        callback(final_msg)
      end
    end)
  else
    -- No URL, just return cached status
    if callback then
      callback(cached_status)
    end
  end
end

---Check if there's a pending suggestion
---@return boolean
function M.has_suggestion()
  if not M.completion then
    return false
  end
  return M.completion.has_suggestion()
end

---Accept current suggestion
function M.accept_suggestion()
  if not M.completion then
    return
  end
  M.completion.accept()
end

---Dismiss current suggestion
function M.dismiss_suggestion()
  if not M.completion then
    return
  end
  M.completion.dismiss()
end

---Request completion manually
function M.request_completion()
  if not M.completion then
    vim.notify("Completion module not loaded", vim.log.levels.WARN)
    return
  end
  M.completion.request()
end

---Accept only the next word of the suggestion
function M.accept_word()
  if not M.completion then
    return
  end
  M.completion.accept_word()
end

---Accept only the next line of the suggestion
function M.accept_line()
  if not M.completion then
    return
  end
  M.completion.accept_line()
end

---Clear completion cache
function M.clear_cache()
  if M.client and M.client.clear_cache then
    M.client.clear_cache()
  end
end

---Reset completion state (useful when completions get stuck)
function M.reset()
  if M.completion and M.completion.reset then
    M.completion.reset()
    vim.notify("OpenCode completion state reset", vim.log.levels.INFO)
  end
end

---Get statusline component
---@return string
function M.statusline()
  local ui = require("opencode.ui")
  return ui.get_statusline()
end

return M
