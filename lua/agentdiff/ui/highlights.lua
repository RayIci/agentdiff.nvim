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
  -- the changed-files panel
  set(0, "AgentdiffPanelTitle", { link = "Title", default = true })
  set(0, "AgentdiffPanelCount", { link = "Comment", default = true })
  set(0, "AgentdiffPanelDir", { link = "Directory", default = true })
  set(0, "AgentdiffPanelDirIcon", { link = "Directory", default = true })
  set(0, "AgentdiffPanelFileIcon", { link = "Normal", default = true })
  set(0, "AgentdiffPanelFold", { link = "Comment", default = true })
  set(0, "AgentdiffPanelPath", { link = "Comment", default = true })
  set(0, "AgentdiffPanelAdded", { link = "Added", default = true })
  set(0, "AgentdiffPanelRemoved", { link = "Removed", default = true })
  set(0, "AgentdiffPanelModified", { link = "Changed", default = true })
  set(0, "AgentdiffPanelCreated", { link = "Added", default = true })
  set(0, "AgentdiffPanelDeleted", { link = "Removed", default = true })
  set(0, "AgentdiffPanelConflicted", { link = "DiagnosticError", default = true })
  set(0, "AgentdiffPanelBinary", { link = "Special", default = true })
  set(0, "AgentdiffPanelDeletedName", { strikethrough = true, default = true })
  set(0, "AgentdiffPanelHelp", { link = "Comment", default = true })
  set(0, "AgentdiffPanelKey", { link = "Special", default = true })
end
return M
