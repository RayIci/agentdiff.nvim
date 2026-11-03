---Harness adapters: one per agent CLI (Claude Code, Copilot CLI, Codex, …).
---An adapter knows how to read the payload its CLI sends to a hook and how to
---install, remove and inspect agentdiff's hook in that CLI's configuration.
---
---Adding a harness = adding harness/<name>.lua that returns an
---AgentdiffHarness and registering it here.
---@class AgentdiffHarnessModule
local M = {}

---What a hook reported: the files an agent is about to edit ("pre") or has
---just edited ("post").
---@class AgentdiffHarnessReport
---@field phase "pre"|"post"
---@field paths string[]   absolute paths
---@field session? string  the harness's session id, when it sends one

---@class AgentdiffHarnessStatus
---@field installed boolean
---@field where string[]   the configuration files holding the hook

---Where to install: the user's home (user scope), the project root (project
---scope), and the state directory baked into the hook command.
---@class AgentdiffHarnessOpts
---@field home string
---@field root string
---@field state_dir string

---@class AgentdiffHarness
---@field name string
---@field parse fun(payload: table, hint?: string): AgentdiffHarnessReport?  nil when the payload is not a file edit
---@field install fun(scope: "user"|"project", opts: AgentdiffHarnessOpts): boolean, string  ok, message
---@field uninstall fun(scope: "user"|"project", opts: AgentdiffHarnessOpts): boolean, string
---@field status fun(opts: AgentdiffHarnessOpts): AgentdiffHarnessStatus

---@type table<string, AgentdiffHarness>
local adapters = {}

---@param adapter AgentdiffHarness
function M.register(adapter)
  adapters[adapter.name] = adapter
end

---@param name string
function M.unregister(name)
  adapters[name] = nil
end

---@param name string
---@return AgentdiffHarness?
function M.get(name)
  return adapters[name]
end

---Names of the registered adapters, sorted.
---@return string[]
function M.names()
  local names = vim.tbl_keys(adapters)
  table.sort(names)
  return names
end

M.register(require("agentdiff.harness.claude"))
M.register(require("agentdiff.harness.copilot"))

return M
