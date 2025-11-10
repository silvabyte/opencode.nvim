---@class OpenCode
---@field config OpenCodeConfig
---@field server OpenCodeServer
---@field client OpenCodeClient
---@field completion OpenCodeCompletion
local M = {}

-- Default configuration
local default_config = {
  server = {
    url = nil,
    port = 4096,
    auto_start = true,
    timeout = 30000,
  },
  completion = {
    enabled = true,
    auto_trigger = true,
    trigger_chars = { ".", ":", ">", " " },
    debounce = 300,
    max_context_lines = 100,
    show_inline = true,
    accept_key = "<Tab>",
    dismiss_key = "<C-e>",
  },
  model = {
    provider = "anthropic",
    model_id = "claude-sonnet-4-5-20250929",
    temperature = 0.7,
  },
  context = {
    include_imports = true,
    include_recent_files = true,
    use_treesitter = true,
    max_tokens = 8000,
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
  },
}

---Setup opencode.nvim
---@param opts? OpenCodeConfig User configuration
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

  -- Auto-start server if configured
  if M.config.server.auto_start and M.server then
    vim.defer_fn(function()
      M.server.start()
    end, 100)
  end

  -- Setup autocommands
  M._setup_autocommands()

  vim.notify("opencode.nvim initialized", vim.log.levels.INFO)
end

---Setup autocommands
function M._setup_autocommands()
  local group = vim.api.nvim_create_augroup("OpenCode", { clear = true })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
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

---Check if OpenCode is available
---@return boolean
function M.is_available()
  if not M.server then
    return false
  end
  return M.server.is_running()
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

---Get server status
---@return string
function M.status()
  if not M.server then
    return "Server module not loaded"
  end

  local running = M.server.is_running()
  local status = running and "Running" or "Stopped"

  if running then
    local url = M.server.get_url()
    return string.format("OpenCode Server: %s (%s)", status, url)
  else
    return string.format("OpenCode Server: %s", status)
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

return M
