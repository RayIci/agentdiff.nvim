---Highlight groups, all defined with `default = true` so colorschemes can
---override them.
---@class AgentdiffHighlights
local M = {}

function M.define()
  local set = vim.api.nvim_set_hl
  set(0, "AgentdiffAdd", { link = "DiffAdd", default = true })
  set(0, "AgentdiffDelete", { link = "DiffDelete", default = true })
  set(0, "AgentdiffHint", { link = "Comment", default = true })
  set(0, "AgentdiffConflict", { link = "DiagnosticWarn", default = true })
  set(0, "AgentdiffTreeFile", { link = "DiagnosticWarn", default = true })
  set(0, "AgentdiffTreeDir", { link = "DiagnosticWarn", default = true })
end
return M
