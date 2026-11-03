---Claude Code: reports the files its Edit, Write, MultiEdit and NotebookEdit
---tools change (`tool_input.file_path`, or `notebook_path`).
---@class AgentdiffClaude: AgentdiffHarness
local M = {}
M.name = "claude"

local payload = require("agentdiff.harness.payload")

---The tools that edit files, and the matcher installed for them.
M.tools = { Edit = true, Write = true, MultiEdit = true, NotebookEdit = true }
M.matcher = "Edit|Write|MultiEdit|NotebookEdit"

---@param p table
---@param hint? string
---@return AgentdiffHarnessReport?
function M.parse(p, hint)
  return payload.report(p, M.tools, hint)
end

return M
