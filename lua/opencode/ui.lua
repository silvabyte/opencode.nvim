---UI components for opencode.nvim
---@class OpenCodeUI
local M = {}

local config = require("opencode.config")

---@type number Extmark namespace ID
local ns_id = nil

---Initialize namespace
local function ensure_namespace()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("opencode_inline")
  end
end

---Show inline completion as virtual text
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param col number Column (0-indexed)
---@param text string Completion text
function M.show_inline_completion(bufnr, row, col, text)
  ensure_namespace()

  local ui_config = config.get_ui()
  local hl_group = ui_config.inline_hl_group or "Comment"

  -- Clear any existing inline completions
  M.hide_inline_completion(bufnr)

  -- Show as virtual text
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, col, {
    virt_text = { { text, hl_group } },
    virt_text_pos = "overlay",
    hl_mode = "combine",
    priority = 100,
  })
end

---Hide inline completion
---@param bufnr? number Buffer number (default: current)
function M.hide_inline_completion(bufnr)
  ensure_namespace()

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear all extmarks in namespace
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

---Show suggestion in floating window
---@param items table[] Completion items
---@param opts? table Options
function M.show_suggestion_window(items, opts)
  opts = opts or {}

  if not items or #items == 0 then
    return
  end

  -- Build content lines
  local lines = {}
  for i, item in ipairs(items) do
    table.insert(lines, string.format("%d. %s", i, item.text or item.label or ""))
    if item.documentation then
      table.insert(lines, "   " .. item.documentation)
    end
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Calculate dimensions
  local width = 50
  local height = math.min(#lines, 10)

  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  -- Create window
  local ui_config = config.get_ui()
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = ui_config.suggestion_border or "rounded",
  })

  -- Auto-close on cursor move
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertLeave" }, {
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  return win
end

---Show loading indicator (non-blocking)
---@param message? string Loading message
function M.show_loading(message)
  message = message or "Loading completions..."
  -- Use echo instead of notify to avoid blocking
  vim.api.nvim_echo({ { "[OpenCode] " .. message, "Comment" } }, false, {})
end

---Hide loading indicator
function M.hide_loading()
  -- Clear the echo area
  vim.api.nvim_echo({ { "", "Normal" } }, false, {})
end

---Update statusline
---@param status string Status message
function M.update_statusline(status)
  local ui_config = config.get_ui()

  if not ui_config.statusline then
    return
  end

  -- Store status in global variable for statusline integration
  vim.g.opencode_status = status
end

---Get statusline component
---@return string status
function M.get_statusline()
  return vim.g.opencode_status or ""
end

return M
