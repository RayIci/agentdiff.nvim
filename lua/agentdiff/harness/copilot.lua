---Copilot CLI: reports the files its file tools change. Its camelCase payloads
---(`toolName`, `toolArgs`) and VS Code-style ones (`tool_name`, `tool_input`,
---with Claude tool names) are both understood.
---@class AgentdiffCopilot: AgentdiffHarness
local M = {}
M.name = "copilot"

local payload = require("agentdiff.harness.payload")

M.tools = {
  edit = true,
  create = true,
  str_replace_editor = true,
  write = true,
  apply_patch = true,
  -- VS Code-style payloads report Claude tool names
  Edit = true,
  Write = true,
  MultiEdit = true,
}
M.matcher = "edit|create|str_replace_editor|write|apply_patch"

---@param p table
---@param hint? string
---@return AgentdiffHarnessReport?
function M.parse(p, hint)
  return payload.report(p, M.tools, hint)
end

return M
