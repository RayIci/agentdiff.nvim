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

local settings = require("agentdiff.harness.settings")

---agentdiff's own hook file (so installing never touches other hook files).
---@param scope "user"|"project"
---@param opts AgentdiffHarnessOpts
---@return string
function M.file(scope, opts)
  if scope == "project" then
    return opts.root .. "/.github/hooks/agentdiff.json"
  end
  return opts.home .. "/.copilot/hooks/agentdiff.json"
end

---@param opts AgentdiffHarnessOpts
---@param phase "pre"|"post"
---@return table
local function entry(opts, phase)
  return {
    type = "command",
    bash = settings.command(M.name, opts.state_dir, phase),
    matcher = M.matcher,
    timeoutSec = 10,
  }
end

---@param scope "user"|"project"
---@param opts AgentdiffHarnessOpts
---@return boolean, string
function M.install(scope, opts)
  local file = M.file(scope, opts)
  local ok, changed = settings.update(file, function()
    return {
      version = 1,
      hooks = { preToolUse = { entry(opts, "pre") }, postToolUse = { entry(opts, "post") } },
    }
  end)
  if not ok then
    return false, tostring(changed)
  end
  return true, (changed and "installed in " or "already installed in ") .. settings.display(file)
end

---@param scope "user"|"project"
---@param opts AgentdiffHarnessOpts
---@return boolean, string
function M.uninstall(scope, opts)
  local file = M.file(scope, opts)
  local ok, changed = settings.update(file, function(data)
    if settings.ours(data) then
      return nil
    end
    return data
  end)
  if not ok then
    return false, tostring(changed)
  end
  return true, (changed and "removed from " or "not installed in ") .. settings.display(file)
end

---@param opts AgentdiffHarnessOpts
---@return AgentdiffHarnessStatus
function M.status(opts)
  local where = {}
  for _, scope in ipairs({ "user", "project" }) do
    local file = M.file(scope, opts)
    local data = settings.read(file)
    if data and settings.ours(data) then
      where[#where + 1] = file
    end
  end
  return { installed = #where > 0, where = where }
end

return M
