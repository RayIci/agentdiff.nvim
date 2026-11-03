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

local settings = require("agentdiff.harness.settings")

local events = { PreToolUse = "pre", PostToolUse = "post" }

---@param scope "user"|"project"
---@param opts AgentdiffHarnessOpts
---@return string
function M.file(scope, opts)
  if scope == "project" then
    return opts.root .. "/.claude/settings.local.json"
  end
  return opts.home .. "/.claude/settings.json"
end

---agentdiff's entry for one hook event.
---@param opts AgentdiffHarnessOpts
---@param phase "pre"|"post"
---@return table
local function entry(opts, phase)
  return {
    matcher = M.matcher,
    hooks = { { type = "command", command = settings.command(M.name, opts.state_dir, phase), timeout = 10 } },
  }
end

---Remove agentdiff's hooks (and lists left empty) from settings data.
---@param data table
---@return table
local function strip(data)
  if type(data.hooks) ~= "table" then
    return data
  end
  for ev, list in pairs(data.hooks) do
    if type(list) == "table" and vim.islist(list) then
      local kept = {}
      for _, e in ipairs(list) do
        if type(e) == "table" and type(e.hooks) == "table" then
          local hooks = vim.tbl_filter(function(h)
            return not settings.ours(h)
          end, e.hooks)
          if #hooks > 0 then
            if #hooks < #e.hooks then
              e.hooks = hooks
            end
            kept[#kept + 1] = e
          end
        elseif not settings.ours(e) then
          kept[#kept + 1] = e
        end
      end
      data.hooks[ev] = #kept > 0 and kept or nil
    end
  end
  if next(data.hooks) == nil then
    data.hooks = nil
  end
  return data
end

---True when the data holds exactly agentdiff's current entries, once each.
---@param data table
---@param opts AgentdiffHarnessOpts
---@return boolean
local function current(data, opts)
  if type(data.hooks) ~= "table" then
    return false
  end
  local found = 0
  for ev, list in pairs(data.hooks) do
    for _, e in ipairs(type(list) == "table" and list or {}) do
      if settings.ours(e) then
        if not (events[ev] and vim.deep_equal(e, entry(opts, events[ev]))) then
          return false
        end
        found = found + 1
      end
    end
  end
  return found == vim.tbl_count(events)
end

---@param scope "user"|"project"
---@param opts AgentdiffHarnessOpts
---@return boolean, string
function M.install(scope, opts)
  local file = M.file(scope, opts)
  local ok, changed = settings.update(file, function(data)
    if current(data, opts) then
      return data
    end
    data = strip(data)
    data.hooks = data.hooks or vim.empty_dict()
    for ev, phase in pairs(events) do
      data.hooks[ev] = data.hooks[ev] or {}
      table.insert(data.hooks[ev], entry(opts, phase))
    end
    return data
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
  local ok, changed = settings.update(file, strip)
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
    if data and settings.ours(data.hooks) then
      where[#where + 1] = file
    end
  end
  return { installed = #where > 0, where = where }
end

return M
