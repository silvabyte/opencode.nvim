---UI components for opencode.nvim
---@class OpenCodeUI
local M = {}

local config = require("opencode.config")

---@type number Extmark namespace ID
local ns_id = nil

---@type number|nil Loading timer for animated indicator
local loading_timer = nil

---@type number Loading animation frame
local loading_frame = 0

---@type string[] Loading animation frames
local loading_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@type number|nil Current loading extmark ID
local loading_extmark = nil

---@type number|nil Buffer where loading indicator is shown
local loading_bufnr = nil

---Initialize namespace
local function ensure_namespace()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("opencode_inline")
  end
end

---Show inline completion as virtual text (supports multi-line)
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param col number Column (0-indexed)
---@param text string Completion text (can be multi-line)
function M.show_inline_completion(bufnr, row, col, text)
  ensure_namespace()

  local ui_config = config.get_ui()
  local hl_group = ui_config.inline_hl_group or "Comment"

  -- Clear any existing inline completions
  M.hide_inline_completion(bufnr)

  -- Split text into lines
  local lines = vim.split(text, "\n", { plain = true })

  if #lines == 0 then
    return
  end

  -- Get current line content for proper positioning
  local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local line_after_cursor = current_line:sub(col + 1)

  -- First line: show as overlay at cursor position
  local first_line = lines[1] or ""

  -- Create virt_lines for additional lines
  local virt_lines = {}
  for i = 2, #lines do
    table.insert(virt_lines, { { lines[i], hl_group } })
  end

  -- Set extmark with both overlay and virtual lines
  local extmark_opts = {
    virt_text = { { first_line, hl_group } },
    virt_text_pos = "overlay",
    hl_mode = "combine",
    priority = 100,
  }

  -- Add virtual lines for multi-line completions
  if #virt_lines > 0 then
    extmark_opts.virt_lines = virt_lines
    extmark_opts.virt_lines_above = false
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, col, extmark_opts)
end

---Hide inline completion
---@param bufnr? number Buffer number (default: current)
function M.hide_inline_completion(bufnr)
  ensure_namespace()

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear all extmarks in namespace
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

---Show loading indicator as animated inline virtual text
---@param bufnr? number Buffer number
---@param row? number Row (0-indexed)
---@param col? number Column (0-indexed)
function M.show_loading(bufnr, row, col)
  ensure_namespace()

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if row == nil or col == nil then
    local cursor = vim.api.nvim_win_get_cursor(0)
    row = cursor[1] - 1
    col = cursor[2]
  end

  loading_bufnr = bufnr
  loading_frame = 0

  -- Start animation timer
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
  end

  local function update_loading()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.hide_loading()
      return
    end

    loading_frame = (loading_frame % #loading_frames) + 1
    local spinner = loading_frames[loading_frame]

    -- Clear previous extmark
    if loading_extmark then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, loading_extmark)
    end

    -- Set new extmark with spinner
    local ok, extmark = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, row, col, {
      virt_text = { { " " .. spinner .. " thinking...", "Comment" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
      priority = 100,
    })

    if ok then
      loading_extmark = extmark
    end
  end

  -- Initial show
  update_loading()

  -- Create timer for animation
  loading_timer = vim.loop.new_timer()
  loading_timer:start(0, 80, vim.schedule_wrap(update_loading))
end

---Hide loading indicator
function M.hide_loading()
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
    loading_timer = nil
  end

  if loading_bufnr and loading_extmark then
    pcall(vim.api.nvim_buf_del_extmark, loading_bufnr, ns_id, loading_extmark)
  end

  loading_extmark = nil
  loading_bufnr = nil

  -- Clear echo area too
  vim.api.nvim_echo({ { "", "Normal" } }, false, {})
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
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Calculate dimensions
  local width = 50
  local height = math.min(#lines, 10)

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

---Create highlight groups for better visuals
function M.setup_highlights()
  -- Define custom highlight group for ghost text if not using Comment
  vim.api.nvim_set_hl(0, "OpenCodeGhostText", {
    fg = "#6b7280",
    italic = true,
    default = true,
  })

  vim.api.nvim_set_hl(0, "OpenCodeLoading", {
    fg = "#9ca3af",
    italic = true,
    default = true,
  })
end

return M
