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
  -- Rough estimate: 1 token ≈ 4 characters
  return math.ceil(#text / 4)
end

---Truncate context to fit token budget
---@param context table Context to truncate
---@param max_tokens number Maximum tokens
---@return table truncated Truncated context
function M.truncate_context(context, max_tokens)
  -- TODO: Implement smart truncation
  -- For now, just return as-is
  return context
end

return M
