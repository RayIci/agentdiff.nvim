---Attribution modes: who changed a file. A mode turns a list of unprocessed
---disk changes into the agent's, the user's, and those to look at again.
---
---Adding a mode = adding attribution/<name>.lua that returns an
---AgentdiffAttribution and registering it here.
---@class AgentdiffAttributionModule
local M = {}

---@class AgentdiffAttributionCtx
---@field mode "poll"|"agent"|"user"   "agent"/"user" force the author (around shell commands)
---@field now integer                  wall-clock ms
---@field guard_moved boolean          the project's HEAD or stash moved since the last poll
---@field produced fun(paths: string[]): table<string, boolean>   content git itself put there
---@field discarded fun(paths: string[]): table<string, boolean>  changes that only move toward HEAD

---@class AgentdiffAttributionResult
---@field agent string[]
---@field user string[]
---@field wait string[]   look again after the settle period

---@class AgentdiffAttribution
---@field name string
---@field classify fun(s: AgentdiffSession, changes: AgentdiffChange[], ctx: AgentdiffAttributionCtx): AgentdiffAttributionResult
---@field reset? fun()  forget per-session state

---@type table<string, AgentdiffAttribution>
local modes = {}

---@param mode AgentdiffAttribution
function M.register(mode)
  modes[mode.name] = mode
end

---@param name string
---@return AgentdiffAttribution?
function M.get(name)
  return modes[name]
end

---The mode in use for a session (the `attribution` option).
---@param s AgentdiffSession
---@return AgentdiffAttribution
function M.active(s)
  return modes[s.opts.attribution] or modes.writer
end

---Names of the registered modes, sorted.
---@return string[]
function M.names()
  local names = vim.tbl_keys(modes)
  table.sort(names)
  return names
end

---Forget every mode's per-session state.
function M.reset()
  for _, m in pairs(modes) do
    if m.reset then
      m.reset()
    end
  end
end

M.register(require("agentdiff.attribution.writer"))

return M
