---Completion source for nvim-cmp
---@class OpenCodeCompletion
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")
local client = require("opencode.client")
local context = require("opencode.context")

---@type table? Current suggestion
local current_suggestion = nil

---@type number? Current buffer
local current_bufnr = nil

---@type number? Row where suggestion was shown
local suggestion_row = nil

---@type number? Col where suggestion was shown
local suggestion_col = nil

---@type number Request ID for deduplication (bumped on each new request)
local completion_request_id = 0

---@type function? Debounced request function
local debounced_request = nil

---@type table? Pre-fetched suggestion waiting to be shown
local prefetched_suggestion = nil

---@type string? Context key for prefetched suggestion
local prefetched_context_key = nil

---@type number Prefetch request ID for deduplication
local prefetch_request_id = 0

---Patterns that often precede needing a completion
local prefetch_triggers = {
  "=$", -- After assignment
  ":%s*$", -- After type annotation
  "->%s*$", -- After arrow
  "=>%s*$", -- After fat arrow
  "return%s+$", -- After return
  "function%s*%(.*%)%s*$", -- After function signature
  "{%s*$", -- After opening brace
  "%(%s*$", -- After opening paren
  ",%s*$", -- After comma
}

---Check if there's a pending suggestion
---@return boolean
function M.has_suggestion()
  return current_suggestion ~= nil
end

---Accept current suggestion
function M.accept()
  if not current_suggestion then
    return false
  end

  -- Capture state before scheduling
  local suggestion = current_suggestion
  local bufnr = current_bufnr or vim.api.nvim_get_current_buf()

  -- Clear state immediately
  current_suggestion = nil
  M.dismiss()

  -- Schedule the actual insertion to avoid E565 when called from other plugin contexts
  vim.schedule(function()
    local row, col = utils.get_cursor_position(bufnr)

    -- Split text into lines
    local text = suggestion.text
    local lines = vim.split(text, "\n", { plain = true })

    -- Insert the completion
    if #lines == 1 then
      -- Single line: insert at cursor
      vim.api.nvim_buf_set_text(bufnr, row, col, row, col, lines)
      -- Move cursor to end
      vim.api.nvim_win_set_cursor(0, { row + 1, col + #lines[1] })
    else
      -- Multi-line: insert as multiple lines
      vim.api.nvim_buf_set_text(bufnr, row, col, row, col, lines)
      -- Move cursor to end of last line
      vim.api.nvim_win_set_cursor(0, { row + #lines, #lines[#lines] })
    end

    utils.debug("Accepted suggestion", { lines = #lines })
  end)

  return true
end

---Accept only the first word of the suggestion
function M.accept_word()
  if not current_suggestion then
    return false
  end

  local text = current_suggestion.text
  -- Find first word boundary (space, newline, or punctuation)
  local word = text:match("^([%w_]+)") or text:match("^([^%s]+)")

  if not word or word == "" then
    return M.accept()
  end

  local bufnr = current_bufnr or vim.api.nvim_get_current_buf()
  local remaining = text:sub(#word + 1)

  -- Update state
  if remaining and remaining ~= "" and not remaining:match("^%s*$") then
    current_suggestion.text = remaining
  else
    current_suggestion = nil
  end

  -- Schedule text insertion
  vim.schedule(function()
    local row, col = utils.get_cursor_position(bufnr)
    vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { word })
    vim.api.nvim_win_set_cursor(0, { row + 1, col + #word })

    -- Show remaining or dismiss
    if current_suggestion then
      M._show_inline_suggestion(bufnr, row, col + #word, current_suggestion.text)
    else
      M.dismiss()
    end
  end)

  return true
end

---Accept only the first line of the suggestion
function M.accept_line()
  if not current_suggestion then
    return false
  end

  local text = current_suggestion.text
  local lines = vim.split(text, "\n", { plain = true })

  if #lines == 0 then
    return false
  end

  local first_line = lines[1]
  local bufnr = current_bufnr or vim.api.nvim_get_current_buf()

  -- Update state
  if #lines > 1 then
    local remaining = table.concat(vim.list_slice(lines, 2), "\n")
    if remaining and remaining ~= "" then
      current_suggestion.text = remaining
    else
      current_suggestion = nil
    end
  else
    current_suggestion = nil
  end

  -- Schedule text insertion
  vim.schedule(function()
    local row, col = utils.get_cursor_position(bufnr)
    vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { first_line })
    vim.api.nvim_win_set_cursor(0, { row + 1, col + #first_line })

    -- Show remaining or dismiss
    if current_suggestion then
      M._show_inline_suggestion(bufnr, row + 1, 0, current_suggestion.text)
    else
      M.dismiss()
    end
  end)

  return true
end

---Dismiss current suggestion
function M.dismiss()
  if not current_suggestion and not current_bufnr then
    return
  end

  current_suggestion = nil
  suggestion_row = nil
  suggestion_col = nil

  -- Clear UI
  if current_bufnr then
    local ui = require("opencode.ui")
    ui.hide_inline_completion(current_bufnr)
    current_bufnr = nil
  end
end

---Force reset all completion state (useful for recovery)
function M.reset()
  -- Bump request IDs to invalidate any pending callbacks
  completion_request_id = completion_request_id + 1
  prefetch_request_id = prefetch_request_id + 1

  -- Cancel any in-flight HTTP request
  client.cancel()

  -- Reset suggestion state
  current_suggestion = nil
  current_bufnr = nil
  suggestion_row = nil
  suggestion_col = nil
  prefetched_suggestion = nil
  prefetched_context_key = nil

  -- Clear UI
  local ui = require("opencode.ui")
  ui.hide_loading()
  ui.hide_inline_completion(vim.api.nvim_get_current_buf())

  utils.debug("Completion state reset")
end

---Generate a context key for caching/prefetching
---@param ctx table Context
---@return string key
local function get_context_key(ctx)
  return string.format(
    "%s:%d:%d:%s",
    ctx.file_path or "",
    ctx.cursor_line or 0,
    ctx.cursor_col or 0,
    ctx.current_line or ""
  )
end

---Check if current line matches any prefetch trigger
---@param line string Current line before cursor
---@return boolean should_prefetch
local function should_prefetch(line)
  for _, pattern in ipairs(prefetch_triggers) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

---Prefetch completion in background (doesn't show UI)
---@param ctx table Context
---@param bufnr number Buffer number
local function prefetch_completion(ctx, _bufnr)
  local context_key = get_context_key(ctx)

  -- Don't prefetch if we already have this context
  if prefetched_context_key == context_key then
    return
  end

  -- Bump prefetch ID to invalidate any previous prefetch
  prefetch_request_id = prefetch_request_id + 1
  local my_prefetch_id = prefetch_request_id

  utils.debug("Prefetching completion", { file = ctx.file_path })

  client.get_completion(ctx, function(success, completions)
    -- Ignore if this prefetch was superseded
    if my_prefetch_id ~= prefetch_request_id then
      utils.debug("Ignoring stale prefetch response")
      return
    end

    if not success or not completions or #completions == 0 then
      return
    end

    -- Store prefetched result
    prefetched_suggestion = completions[1]
    prefetched_context_key = context_key

    utils.debug("Prefetched completion ready", { text = prefetched_suggestion.text:sub(1, 30) })
  end)
end

---Try to use prefetched suggestion if context matches
---@param ctx table Current context
---@return boolean used Whether prefetched suggestion was used
local function try_use_prefetch(ctx)
  if not prefetched_suggestion then
    return false
  end

  local context_key = get_context_key(ctx)

  -- Check if prefetch matches current context
  if prefetched_context_key ~= context_key then
    -- Context changed, invalidate prefetch
    prefetched_suggestion = nil
    prefetched_context_key = nil
    return false
  end

  -- Use the prefetched suggestion
  current_suggestion = prefetched_suggestion
  prefetched_suggestion = nil
  prefetched_context_key = nil

  return true
end

---Request completion manually
function M.request()
  local bufnr = vim.api.nvim_get_current_buf()

  if not utils.is_valid_buffer(bufnr) then
    utils.debug("Invalid buffer for completion")
    return
  end

  -- Dismiss any existing suggestion
  M.dismiss()

  -- Extract context
  local ctx = context.extract(bufnr)

  -- Request completion
  M._request_completion(ctx, bufnr)
end

---Internal completion request
---@param ctx table Context
---@param bufnr number Buffer number
function M._request_completion(ctx, bufnr)
  local ui = require("opencode.ui")
  local row, col = utils.get_cursor_position(bufnr)

  -- Try to use prefetched completion first (instant!)
  if try_use_prefetch(ctx) then
    utils.debug("Using prefetched completion")
    current_bufnr = bufnr
    suggestion_row = row
    suggestion_col = col
    M._show_inline_suggestion(bufnr, row, col, current_suggestion.text)
    return
  end

  -- Bump request ID to invalidate any previous request and cancel in-flight HTTP
  completion_request_id = completion_request_id + 1
  local my_request_id = completion_request_id

  -- Cancel any in-flight request (kills the curl process)
  client.cancel()

  utils.debug("Requesting completion", { file = ctx.file_path, request_id = my_request_id })

  ui.show_loading(bufnr, row, col)

  client.get_completion(ctx, function(success, completions)
    -- Ignore stale responses (request was superseded by a newer one)
    if my_request_id ~= completion_request_id then
      utils.debug("Ignoring stale completion response", { request_id = my_request_id })
      return
    end

    -- Hide loading indicator
    ui.hide_loading()

    -- Check if buffer is still valid
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local current_row, current_col = utils.get_cursor_position(bufnr)
    if current_row ~= row then
      utils.debug("Cursor moved to different line, discarding completion")
      return
    end

    if not success then
      utils.debug("Completion failed", { error = completions })
      return
    end

    if not completions or #completions == 0 then
      utils.debug("No completions returned")
      return
    end

    -- Store first suggestion
    current_suggestion = completions[1]
    current_bufnr = bufnr
    suggestion_row = current_row
    suggestion_col = current_col

    utils.debug("Got completion", { text = current_suggestion.text:sub(1, 50) })

    -- Show inline suggestion (full multi-line)
    M._show_inline_suggestion(bufnr, current_row, current_col, current_suggestion.text)
  end)
end

---Show inline suggestion as ghost text
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param col number Column (0-indexed)
---@param text string Suggestion text
function M._show_inline_suggestion(bufnr, row, col, text)
  local ui = require("opencode.ui")

  -- Show full multi-line ghost text
  ui.show_inline_completion(bufnr, row, col, text)

  utils.debug("Showing inline completion", { lines = #vim.split(text, "\n") })
end

---Check if cursor movement should dismiss the suggestion
---@param old_row number Previous row
---@param old_col number Previous column
---@param new_row number New row
---@param new_col number New column
---@return boolean should_dismiss
local function should_dismiss_on_move(old_row, old_col, new_row, new_col)
  -- Always dismiss if row changed
  if new_row ~= old_row then
    return true
  end

  -- Dismiss if cursor moved backwards
  if new_col < old_col then
    return true
  end

  -- Allow forward movement (user might be looking at the suggestion)
  return false
end

---Setup autocommands for auto-trigger
function M.setup_autocmds()
  local completion_config = config.get_completion()

  local group = vim.api.nvim_create_augroup("OpenCodeCompletion", { clear = true })

  -- Create debounced request function
  debounced_request = utils.debounce(function()
    if not completion_config.enabled then
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_valid_buffer(bufnr) then
      return
    end

    -- Don't auto-trigger if there's already a suggestion
    if current_suggestion then
      return
    end

    local ctx = context.extract(bufnr)
    M._request_completion(ctx, bufnr)
  end, completion_config.debounce)

  -- Create prefetch function (triggers on common patterns)
  local debounced_prefetch = utils.debounce(function()
    if not completion_config.enabled then
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_valid_buffer(bufnr) then
      return
    end

    -- Get current line before cursor
    local _, col = utils.get_cursor_position(bufnr)
    local current_line = utils.get_current_line(bufnr)
    local line_before_cursor = current_line:sub(1, col)

    -- Check if we should prefetch
    if should_prefetch(line_before_cursor) then
      local ctx = context.extract(bufnr)
      prefetch_completion(ctx, bufnr)
    end
  end, 50) -- Very short debounce for prefetch

  -- Trigger on text change in insert mode (only if auto_trigger is enabled)
  if completion_config.auto_trigger then
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
      group = group,
      callback = function()
        -- Dismiss current suggestion on text change
        M.dismiss()
        -- Request new completion
        debounced_request()
        -- Also check for prefetch opportunity
        debounced_prefetch()
      end,
    })
  else
    -- Even without auto-trigger, do prefetching for snappier manual triggers
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
      group = group,
      callback = function()
        -- Dismiss current suggestion on text change
        M.dismiss()
        -- Check for prefetch opportunity
        debounced_prefetch()
      end,
    })
  end

  -- Smart cursor movement handling
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = group,
    callback = function()
      if not current_suggestion then
        return
      end

      local row, col = utils.get_cursor_position()

      -- Check if we should dismiss
      if suggestion_row and suggestion_col then
        if should_dismiss_on_move(suggestion_row, suggestion_col, row, col) then
          M.dismiss()
        end
      end
    end,
  })

  -- Clear suggestion when leaving insert mode
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      M.dismiss()
    end,
  })

  -- Setup keybindings
  M._setup_keymaps()
end

---Setup keymaps for completion
function M._setup_keymaps()
  local completion_config = config.get_completion()

  -- Tab - Accept full suggestion (smart: falls through to normal tab if no suggestion)
  vim.keymap.set("i", completion_config.accept_key or "<Tab>", function()
    if M.has_suggestion() then
      return M.accept() and "" or "<Tab>"
    end
    -- Return actual tab if no suggestion
    return "<Tab>"
  end, {
    expr = true,
    noremap = true,
    silent = true,
    desc = "Accept OpenCode suggestion or insert tab",
  })

  -- Ctrl+Right - Accept word
  vim.keymap.set("i", "<C-Right>", function()
    if M.has_suggestion() then
      M.accept_word()
      return ""
    end
    return "<C-Right>"
  end, { expr = true, noremap = true, silent = true, desc = "Accept next word of suggestion" })

  -- Ctrl+Down or Ctrl+Enter - Accept line
  vim.keymap.set("i", "<C-l>", function()
    if M.has_suggestion() then
      M.accept_line()
      return ""
    end
    return "<C-l>"
  end, { expr = true, noremap = true, silent = true, desc = "Accept next line of suggestion" })

  -- Escape or Ctrl+E - Dismiss suggestion
  vim.keymap.set("i", completion_config.dismiss_key or "<C-e>", function()
    if M.has_suggestion() then
      M.dismiss()
      return ""
    end
    return completion_config.dismiss_key or "<C-e>"
  end, { expr = true, noremap = true, silent = true, desc = "Dismiss OpenCode suggestion" })

  -- Ctrl+] - Manual trigger (already set in plugin/opencode.vim but ensure it works)
  vim.keymap.set("i", "<C-]>", function()
    M.request()
  end, { noremap = true, silent = true, desc = "Request OpenCode completion" })
end

---nvim-cmp source
M.source = {}

function M.source.new()
  return setmetatable({}, { __index = M.source })
end

function M.source:is_available()
  local completion_config = config.get_completion()
  return completion_config.enabled
end

function M.source:get_debug_name()
  return "opencode"
end

function M.source:complete(params, callback)
  local bufnr = params.context.bufnr

  if not utils.is_valid_buffer(bufnr) then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- Extract context
  local ctx = context.extract(bufnr)

  -- Request completion
  client.get_completion(ctx, function(success, completions)
    if not success or not completions then
      callback({ items = {}, isIncomplete = false })
      return
    end

    -- Convert to nvim-cmp format
    local items = {}
    for _, completion in ipairs(completions) do
      table.insert(items, {
        label = completion.text or "",
        kind = vim.lsp.protocol.CompletionItemKind.Text,
        insertText = completion.text or "",
        documentation = completion.documentation or "",
      })
    end

    callback({ items = items, isIncomplete = false })
  end)
end

return M
