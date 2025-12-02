# AGENTS.md

## Build/Lint Commands
- `make fmt` - Format code with stylua
- `make lint` - Lint code with selene
- `make check` - Run both fmt and lint
- No test framework configured

## Code Style
- **Formatter:** stylua (2-space indent, 100 col width, double quotes, always use parens)
- **Linter:** selene with `lua51+vim` standard
- **Module pattern:** `local M = {} ... return M`
- **Naming:** `snake_case` for functions/variables, `_prefix` for private, `SCREAMING_CASE` for constants
- **Types:** Use LuaDoc annotations (`---@class`, `---@param`, `---@return`, `---@field`)
- **Imports:** Top of file, `local foo = require("opencode.foo")`

## Error Handling
- Use `pcall` for safe requires and risky operations
- Guard clauses with early returns for invalid state
- `vim.notify(msg, vim.log.levels.ERROR)` for user-facing errors

## Async Patterns
- `vim.defer_fn(fn, ms)` for delays, `vim.schedule(fn)` for next tick
- Callback-based async (no coroutines), e.g. `fn(ctx, function(ok, result) end)`

## Issue Tracking (Beads)
This repo uses [Beads](https://github.com/steveyegge/beads) for AI-native issue tracking. Issues live in `.beads/issues.jsonl`.

**Common commands:**
- `bd list` - View all issues
- `bd show <id>` - View issue details
- `bd create "title"` - Create new issue
- `bd update <id> --status in-progress|done` - Update status
- `bd sync` - Sync with git remote
