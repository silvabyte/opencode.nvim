---Configuration management for opencode.nvim
---User config (all fields optional, merged with defaults)
---@class OpenCodeConfig
---@field server? OpenCodeServerConfig
---@field completion? OpenCodeCompletionConfig
---@field model? OpenCodeModelConfig
---@field context? OpenCodeContextConfig
---@field session? OpenCodeSessionConfig
---@field ui? OpenCodeUIConfig

---@class OpenCodeServerConfig
---@field url? string Server URL (nil = auto-start)
---@field port? number Server port
---@field auto_start? boolean Auto-start server
---@field timeout? number Request timeout in ms

---@class OpenCodeCompletionConfig
---@field enabled? boolean Enable completions
---@field auto_trigger? boolean Auto-trigger on typing
---@field trigger_chars? string[] Characters that trigger completion
---@field debounce? number Debounce delay in ms
---@field max_context_lines? number Max lines of context
---@field show_inline? boolean Show inline suggestions
---@field accept_key? string Key to accept suggestion
---@field dismiss_key? string Key to dismiss suggestion

---@class OpenCodeModelConfig
---@field provider? string AI provider
---@field model_id? string Model identifier
---@field temperature? number Temperature setting

---@class OpenCodeContextConfig
---@field include_imports? boolean Include import statements
---@field include_recent_files? boolean Include recently edited files
---@field use_treesitter? boolean Use Tree-sitter for parsing
---@field max_tokens? number Maximum context tokens

---@class OpenCodeSessionConfig
---@field per_project? boolean One session per project
---@field persist? boolean Persist sessions
---@field auto_cleanup? boolean Auto cleanup old sessions

---@class OpenCodeUIConfig
---@field inline_hl_group? string Highlight group for inline text
---@field suggestion_border? string Border style for windows
---@field statusline? boolean Show in statusline

local M = {}

---@type OpenCodeConfig
M._config = nil

---Setup configuration
---@param opts? OpenCodeConfig User configuration (merged with defaults)
function M.setup(opts)
  M._config = opts or {}
end

---Get configuration
---@return OpenCodeConfig
function M.get()
  if not M._config then
    error("OpenCode not configured. Call setup() first.")
  end
  return M._config
end

---Get server configuration
---@return OpenCodeServerConfig
function M.get_server()
  return M.get().server
end

---Get completion configuration
---@return OpenCodeCompletionConfig
function M.get_completion()
  return M.get().completion
end

---Get model configuration
---@return OpenCodeModelConfig
function M.get_model()
  return M.get().model
end

---Get context configuration
---@return OpenCodeContextConfig
function M.get_context()
  return M.get().context
end

---Get session configuration
---@return OpenCodeSessionConfig
function M.get_session()
  return M.get().session
end

---Get UI configuration
---@return OpenCodeUIConfig
function M.get_ui()
  return M.get().ui
end

---Update configuration value
---@param path string Dot-separated path (e.g., "completion.enabled")
---@param value any New value
function M.set(path, value)
  local keys = vim.split(path, ".", { plain = true })
  local config = M.get()

  local current = config
  for i = 1, #keys - 1 do
    if current[keys[i]] == nil then
      current[keys[i]] = {}
    end
    current = current[keys[i]]
  end

  current[keys[#keys]] = value
end

---Validate configuration
---@return boolean, string? success, error message
function M.validate()
  local config = M._config
  if not config then
    return false, "No configuration loaded"
  end

  -- Validate server config
  if config.server then
    if config.server.port and (config.server.port < 1024 or config.server.port > 65535) then
      return false, "Invalid server port (must be 1024-65535)"
    end
  end

  -- Validate completion config
  if config.completion then
    if config.completion.debounce and config.completion.debounce < 0 then
      return false, "Invalid debounce value (must be >= 0)"
    end
  end

  -- Validate model config
  if config.model then
    if not config.model.provider or config.model.provider == "" then
      return false, "Model provider is required"
    end
    if not config.model.model_id or config.model.model_id == "" then
      return false, "Model ID is required"
    end
  end

  return true
end

return M
