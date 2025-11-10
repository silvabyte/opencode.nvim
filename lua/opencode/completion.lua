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

---Check if there's a pending suggestion
---@return boolean
function M.has_suggestion()
  return current_suggestion ~= nil
end

---Accept current suggestion
function M.accept()
  if not current_suggestion then
    return
  end

  local bufnr = current_bufnr or vim.api.nvim_get_current_buf()
  local row, col = utils.get_cursor_position(bufnr)

  -- Split text into lines
  local text = current_suggestion.text
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

  -- Clear suggestion UI
  M.dismiss()

  utils.info("Completion accepted")
  utils.debug("Accepted suggestion", { lines = #lines })
end

---Dismiss current suggestion
function M.dismiss()
  if not current_suggestion and not current_bufnr then
    return
  end

  current_suggestion = nil

  -- Clear UI
  if current_bufnr then
    local ui = require("opencode.ui")
    ui.hide_inline_completion(current_bufnr)
    current_bufnr = nil
  end
end

---Request completion manually
function M.request()
  local bufnr = vim.api.nvim_get_current_buf()

  if not utils.is_valid_buffer(bufnr) then
    utils.debug("Invalid buffer for completion")
    return
  end

  -- Extract context
  local ctx = context.extract(bufnr)

  -- Request completion
  M._request_completion(ctx, bufnr)
end

---Internal completion request
---@param ctx table Context
---@param bufnr number Buffer number
function M._request_completion(ctx, bufnr)
  utils.debug("Requesting completion", { file = ctx.file_path })

  local ui = require("opencode.ui")
  ui.show_loading("Getting completion...")

  client.get_completion(ctx, function(success, completions)
    ui.hide_loading()

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

    utils.debug("Got completion", { text = current_suggestion.text })

    -- Show inline suggestion
    local row, col = utils.get_cursor_position(bufnr)
    M._show_inline_suggestion(bufnr, row, col, current_suggestion.text)
  end)
end

---Show inline suggestion as ghost text
---@param bufnr number Buffer number
---@param row number Row (0-indexed)
---@param col number Column (0-indexed)
---@param text string Suggestion text
function M._show_inline_suggestion(bufnr, row, col, text)
  local ui = require("opencode.ui")

  -- For multi-line completions, only show the first line inline
  local lines = vim.split(text, "\n", { plain = true })
  local inline_text = lines[1] or text

  -- Show as ghost text at cursor position
  ui.show_inline_completion(bufnr, row, col, inline_text)

  utils.info("Completion ready - press <Tab> to accept")
end

---Setup autocommands for auto-trigger
function M.setup_autocmds()
  local completion_config = config.get_completion()

  if not completion_config.auto_trigger then
    return
  end

  local group = vim.api.nvim_create_augroup("OpenCodeCompletion", { clear = true })

  -- Debounced completion request
  local debounced_request = utils.debounce(function()
    if not completion_config.enabled then
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    if not utils.is_valid_buffer(bufnr) then
      return
    end

    local ctx = context.extract(bufnr)
    M._request_completion(ctx, bufnr)
  end, completion_config.debounce)

  -- Trigger on text change in insert mode
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = group,
    callback = function()
      debounced_request()
    end,
  })

  -- Clear suggestion on cursor move
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      M.dismiss()
    end,
  })

  -- Clear suggestion when leaving insert mode
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      M.dismiss()
    end,
  })
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
