---UI components for opencode.nvim
---@class OpenCodeUI
local M = {}

local config = require("opencode.config")

---@type number Extmark namespace ID
local ns_id = nil

---@type number|nil Loading timer for animated indicator
local loading_timer = nil

---@type number|nil Delay timer before showing loading indicator
local loading_delay_timer = nil

---@type number Loading animation frame
local loading_frame = 0

---@type string[] Loading animation frames (compact spinner)
local loading_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@type number|nil Current loading extmark ID
local loading_extmark = nil

---@type number|nil Buffer where loading indicator is shown
local loading_bufnr = nil

---@type number|nil Row where loading indicator is shown (reserved for future use)
local _loading_row = nil

---@type boolean Whether loading indicator is currently visible
local loading_visible = false

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

  -- Get current line content for proper positioning (reserved for future use)
  -- local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

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

---Start the actual loading animation (called after delay)
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param indicator_mode string Loading indicator mode
local function start_loading_animation(bufnr, row, indicator_mode)
  loading_visible = true
  loading_frame = 0

  local function update_loading()
    if not loading_visible then
      return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.hide_loading()
      return
    end

    loading_frame = (loading_frame % #loading_frames) + 1
    local spinner = loading_frames[loading_frame]

    if indicator_mode == "eol" then
      -- Clear previous extmark
      if loading_extmark then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, loading_extmark)
      end

      -- Set new extmark at end of line (non-intrusive)
      local ok, extmark = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, row, 0, {
        virt_text = { { " " .. spinner, "OpenCodeLoading" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 50, -- Lower priority so it doesn't conflict with other plugins
      })

      if ok then
        loading_extmark = extmark
      end
    elseif indicator_mode == "statusline" then
      -- Update statusline with spinner
      vim.g.opencode_loading = spinner
      -- Force statusline redraw
      vim.cmd("redrawstatus")
    end
    -- "none" mode: do nothing visible
  end

  -- Initial show
  update_loading()

  -- Create timer for animation (slightly slower for less distraction)
  loading_timer = vim.loop.new_timer()
  loading_timer:start(0, 100, vim.schedule_wrap(update_loading))
end

---Show loading indicator (with optional delay to avoid flicker)
---@param bufnr? number Buffer number
---@param row? number Row (0-indexed)
---@param _col? number Column (0-indexed, unused but kept for API compatibility)
function M.show_loading(bufnr, row, _col)
  ensure_namespace()

  local ui_config = config.get_ui()
  local indicator_mode = ui_config.loading_indicator or "eol"
  local delay = ui_config.loading_delay or 100

  -- If mode is "none", don't show anything
  if indicator_mode == "none" then
    return
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if row == nil then
    local cursor = vim.api.nvim_win_get_cursor(0)
    row = cursor[1] - 1
  end

  -- Store state
  loading_bufnr = bufnr
  _loading_row = row

  -- Cancel any existing delay timer
  if loading_delay_timer then
    loading_delay_timer:stop()
    loading_delay_timer:close()
    loading_delay_timer = nil
  end

  -- Cancel any existing animation timer
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
    loading_timer = nil
  end

  -- Clear any existing loading indicator
  if loading_extmark then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, loading_extmark)
    loading_extmark = nil
  end

  -- If delay is 0 or less, show immediately
  if delay <= 0 then
    start_loading_animation(bufnr, row, indicator_mode)
    return
  end

  -- Start delay timer before showing loading indicator
  loading_delay_timer = vim.loop.new_timer()
  loading_delay_timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      loading_delay_timer = nil
      -- Only show if we haven't been cancelled
      if loading_bufnr == bufnr then
        start_loading_animation(bufnr, row, indicator_mode)
      end
    end)
  )
end

---Hide loading indicator
function M.hide_loading()
  loading_visible = false

  -- Cancel delay timer if pending
  if loading_delay_timer then
    loading_delay_timer:stop()
    loading_delay_timer:close()
    loading_delay_timer = nil
  end

  -- Stop animation timer
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
    loading_timer = nil
  end

  -- Clear extmark
  if loading_bufnr and loading_extmark then
    pcall(vim.api.nvim_buf_del_extmark, loading_bufnr, ns_id, loading_extmark)
  end

  loading_extmark = nil
  loading_bufnr = nil
  _loading_row = nil

  -- Clear statusline loading indicator
  vim.g.opencode_loading = nil
end

---Check if loading indicator is active
---@return boolean
function M.is_loading()
  return loading_visible or loading_delay_timer ~= nil
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
  -- Show loading spinner if active (when using statusline mode)
  local loading = vim.g.opencode_loading
  if loading then
    return loading .. " "
  end
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
