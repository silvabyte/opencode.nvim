---Session management for OpenCode
---@class OpenCodeSession
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")
local client = require("opencode.client")

---@type table<string, table> Active sessions (keyed by project root)
local sessions = {}

---Get or create session for buffer
---@param bufnr number Buffer number
---@param callback function Callback(success, session)
function M.get_or_create(bufnr, callback)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project_root = utils.get_project_root(file_path)

  -- Check if session exists
  if sessions[project_root] then
    callback(true, sessions[project_root])
    return
  end

  -- Create new session
  client.create_session(project_root, function(success, session)
    if not success then
      callback(false, "Failed to create session: " .. tostring(session))
      return
    end

    -- Store session
    sessions[project_root] = {
      id = session.id,
      project_root = project_root,
      created_at = os.time(),
      buffers = { bufnr },
    }

    utils.debug("Created session for project", { root = project_root, id = session.id })
    callback(true, sessions[project_root])
  end)
end

---Create new session manually
function M.create_new()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project_root = utils.get_project_root(file_path)

  client.create_session(project_root, function(success, session)
    if not success then
      utils.error("Failed to create session: " .. tostring(session))
      return
    end

    -- Store session
    sessions[project_root] = {
      id = session.id,
      project_root = project_root,
      created_at = os.time(),
      buffers = { bufnr },
    }

    utils.info("Created new session: " .. session.id)
  end)
end

---List all sessions
function M.list()
  client.list_sessions(function(success, session_list)
    if not success then
      utils.error("Failed to list sessions: " .. tostring(session_list))
      return
    end

    if not session_list or #session_list == 0 then
      utils.info("No active sessions")
      return
    end

    -- Display sessions
    local lines = { "Active OpenCode sessions:" }
    for _, session in ipairs(session_list) do
      table.insert(
        lines,
        string.format("  - %s (%s)", session.id, session.directory or "unknown")
      )
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end)
end

---Cleanup old sessions
function M.cleanup_sessions()
  local session_config = config.get_session()

  if not session_config.auto_cleanup then
    return
  end

  -- Clean up local session registry
  for project_root, session in pairs(sessions) do
    -- TODO: Add age-based cleanup
    sessions[project_root] = nil
  end

  utils.debug("Cleaned up sessions")
end

---Delete session
---@param session_id string Session ID
function M.delete(session_id)
  client.delete_session(session_id, function(success, result)
    if not success then
      utils.error("Failed to delete session: " .. tostring(result))
      return
    end

    -- Remove from local registry
    for project_root, session in pairs(sessions) do
      if session.id == session_id then
        sessions[project_root] = nil
        break
      end
    end

    utils.info("Deleted session: " .. session_id)
  end)
end

---Get session for project root
---@param project_root string Project root
---@return table? session
function M.get(project_root)
  return sessions[project_root]
end

return M
