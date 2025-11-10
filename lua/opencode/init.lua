---Main opencode module
---@class OpenCodeModule
local M = {}

-- Re-export main opencode functions
setmetatable(M, {
  __index = function(_, key)
    return require("opencode")[key]
  end,
})

return M
