---Context extraction for completions
---@class OpenCodeContext
local M = {}

local config = require("opencode.config")
local utils = require("opencode.utils")

---Extract context from buffer
---@param bufnr number Buffer number
---@return table context
function M.extract(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local context_config = config.get_context()
  local row, col = utils.get_cursor_position(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  -- Get lines before cursor (keep small to avoid context overflow)
  local max_before = 15  -- Reduced from 50
  local start_line = math.max(0, row - max_before)
  local content_before = utils.get_buffer_lines(bufnr, start_line, row)

  -- Get lines after cursor
  local max_after = 5  -- Reduced for efficiency
  local content_after = utils.get_buffer_lines(bufnr, row + 1, row + 1 + max_after)

  -- Get current line
  local current_line = utils.get_current_line(bufnr)

  -- Get project root
  local project_root = utils.get_project_root(file_path)

  local context = {
    file_path = file_path,
    language = filetype,
    cursor_line = row,
    cursor_col = col,
    content_before = content_before,
    content_after = content_after,
    current_line = current_line,
    project_root = project_root,
  }

  -- Add tree-sitter context if enabled
  if context_config.use_treesitter then
    local ts_context = M._extract_treesitter_context(bufnr, row, col)
    context.treesitter = ts_context
  end

  -- Add imports if enabled
  if context_config.include_imports then
    local imports = M._extract_imports(bufnr, filetype)
    context.imports = imports
  end

  return context
end

---Extract tree-sitter context
---@param bufnr number Buffer number
---@param row number Cursor row (0-indexed)
---@param col number Cursor column (0-indexed)
---@return table? context Tree-sitter context or nil
function M._extract_treesitter_context(bufnr, row, col)
  -- Check if tree-sitter is available
  local has_ts, _ = pcall(require, "nvim-treesitter")
  if not has_ts then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()

  -- Find node at cursor
  local cursor_node = root:descendant_for_range(row, col, row, col)
  if not cursor_node then
    return nil
  end

  -- Find enclosing function/class
  local function_node = M._find_parent_node(cursor_node, {
    "function_declaration",
    "function_definition",
    "method_declaration",
    "method_definition",
    "arrow_function",
    "function_expression",
  })

  local class_node = M._find_parent_node(cursor_node, {
    "class_declaration",
    "class_definition",
  })

  return {
    cursor_node_type = cursor_node:type(),
    function_node = function_node and function_node:type() or nil,
    class_node = class_node and class_node:type() or nil,
  }
end

---Find parent node of specific types
---@param node table Tree-sitter node
---@param types string[] Node types to search for
---@return table? node Found node or nil
function M._find_parent_node(node, types)
  local current = node:parent()
  while current do
    local node_type = current:type()
    for _, type in ipairs(types) do
      if node_type == type then
        return current
      end
    end
    current = current:parent()
  end
  return nil
end

---Extract import statements
---@param bufnr number Buffer number
---@param filetype string File type
---@return string[] imports
function M._extract_imports(bufnr, filetype)
  local imports = {}
  local lines = utils.get_buffer_lines(bufnr)

  -- Simple pattern matching for common import statements
  local patterns = {
    lua = "^require%s*%(",
    python = "^import%s+",
    javascript = "^import%s+",
    typescript = "^import%s+",
    go = "^import%s+",
    rust = "^use%s+",
  }

  local pattern = patterns[filetype]
  if not pattern then
    return imports
  end

  for _, line in ipairs(lines) do
    if line:match(pattern) then
      table.insert(imports, line)
    end
  end

  return imports
end

---Calculate token count (rough estimate)
---@param text string Text to count
---@return number tokens Estimated token count
function M.estimate_tokens(text)
  -- Rough estimate: 1 token ≈ 4 characters for code
  return math.ceil(#text / 4)
end

---Smart truncate lines to fit token budget
---@param lines string[] Lines to truncate
---@param max_tokens number Maximum tokens
---@param keep_end boolean If true, keep lines from end; if false, from start
---@return string[] truncated Truncated lines
function M._truncate_lines(lines, max_tokens, keep_end)
  local total_tokens = 0
  local result = {}

  if keep_end then
    -- Keep lines from the end (for before-cursor context)
    for i = #lines, 1, -1 do
      local line_tokens = M.estimate_tokens(lines[i])
      if total_tokens + line_tokens > max_tokens then
        break
      end
      table.insert(result, 1, lines[i])
      total_tokens = total_tokens + line_tokens
    end
  else
    -- Keep lines from the start (for after-cursor context)
    for i = 1, #lines do
      local line_tokens = M.estimate_tokens(lines[i])
      if total_tokens + line_tokens > max_tokens then
        break
      end
      table.insert(result, lines[i])
      total_tokens = total_tokens + line_tokens
    end
  end

  return result
end

---Truncate context to fit token budget with smart prioritization
---@param context table Context to truncate
---@param max_tokens number Maximum tokens
---@return table truncated Truncated context
function M.truncate_context(context, max_tokens)
  local truncated = vim.deepcopy(context)

  -- Budget allocation (prioritize before-cursor context)
  local before_budget = math.floor(max_tokens * 0.7) -- 70% for before
  local after_budget = math.floor(max_tokens * 0.2)  -- 20% for after
  local current_budget = math.floor(max_tokens * 0.1) -- 10% for current line

  -- Truncate before context (keep most recent lines)
  if truncated.content_before then
    truncated.content_before = M._truncate_lines(
      truncated.content_before,
      before_budget,
      true -- keep from end
    )
  end

  -- Truncate after context (keep closest lines)
  if truncated.content_after then
    truncated.content_after = M._truncate_lines(
      truncated.content_after,
      after_budget,
      false -- keep from start
    )
  end

  -- Truncate current line if too long
  if truncated.current_line and M.estimate_tokens(truncated.current_line) > current_budget then
    local cursor_col = truncated.cursor_col or 0
    -- Keep characters around cursor
    local keep_chars = current_budget * 4
    local start_pos = math.max(0, cursor_col - math.floor(keep_chars / 2))
    local end_pos = math.min(#truncated.current_line, cursor_col + math.floor(keep_chars / 2))
    truncated.current_line = truncated.current_line:sub(start_pos + 1, end_pos)
    truncated.cursor_col = cursor_col - start_pos
  end

  return truncated
end

---Get a compact context summary for better completions
---@param bufnr number Buffer number
---@return table context Compact context
function M.extract_compact(bufnr)
  local full_context = M.extract(bufnr)
  local context_config = config.get_context()
  local max_tokens = context_config.max_tokens or 4000

  return M.truncate_context(full_context, max_tokens)
end

return M
