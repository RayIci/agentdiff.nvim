---Managing agentdiff's hook in agent CLIs: install, uninstall, status.
---@class AgentdiffHooksActions
local M = {}

local config = require("agentdiff.config")
local harness = require("agentdiff.harness")
local journal = require("agentdiff.core.journal")
local session = require("agentdiff.core.session")
local store = require("agentdiff.core.store")
local util = require("agentdiff.core.util")

M.scopes = { "user", "project" }

---@return string
local function root()
  local s = session.get()
  return s and s.root or store.resolve_root(config.options)
end

---Where to install, with the state directory as an absolute path.
---@return AgentdiffHarnessOpts
function M.opts()
  local state_dir = vim.fn.fnamemodify(config.state_dir(), ":p"):gsub("/+$", "")
  return { home = vim.env.HOME or "~", root = root(), state_dir = state_dir }
end

---@param name? string  a harness name, "all" or nil (all)
---@return string[]? names
---@return string? err
local function targets(name)
  if name == nil or name == "" or name == "all" then
    return harness.names()
  end
  if harness.get(name) then
    return { name }
  end
  return nil, ("unknown harness '%s' (valid: all, %s)"):format(name, table.concat(harness.names(), ", "))
end

---@param op "install"|"uninstall"
---@param name? string
---@param scope? string
---@return boolean ok
---@return string[] lines
local function run(op, name, scope)
  scope = scope or "user"
  if not vim.tbl_contains(M.scopes, scope) then
    return false, { ("unknown scope '%s' (valid: user, project)"):format(scope) }
  end
  local names, err = targets(name)
  if not names then
    return false, { err }
  end
  local opts, lines, all_ok = M.opts(), {}, true
  for _, n in ipairs(names) do
    local ok, msg = harness.get(n)[op](scope, opts)
    all_ok = all_ok and ok
    lines[#lines + 1] = n .. ": " .. msg
  end
  return all_ok, lines
end

---@param op "install"|"uninstall"
---@param name? string
---@param scope? string
---@return boolean
local function report(op, name, scope)
  local ok, lines = run(op, name, scope)
  if ok and op == "install" and config.options.attribution ~= "hooks" then
    lines[#lines + 1] = 'set attribution = "hooks" in setup() to review only what agents report'
  end
  util.notify(
    "agentdiff hooks " .. op .. "\n" .. table.concat(lines, "\n"),
    ok and vim.log.levels.INFO or vim.log.levels.ERROR
  )
  return ok
end

---Install agentdiff's hook for a harness ("claude", "copilot", "all" or nil)
---at "user" (default) or "project" scope.
---@param name? string
---@param scope? "user"|"project"
---@return boolean ok
function M.install(name, scope)
  return report("install", name, scope)
end

---@param name? string
---@param scope? "user"|"project"
---@return boolean ok
function M.uninstall(name, scope)
  return report("uninstall", name, scope)
end

---True when any harness has agentdiff's hook, at user scope or for the
---current project.
---@return boolean
function M.any_installed()
  local o = M.opts()
  for _, n in ipairs(harness.names()) do
    local ok, st = pcall(harness.get(n).status, o)
    if ok and st and st.installed then
      return true
    end
  end
  return false
end

local noticed = false

---In the hooks mode with no hook installed anywhere, nothing would ever be
---reviewed: say so, once per Neovim instance.
function M.notice_missing()
  if noticed or config.options.attribution ~= "hooks" or M.any_installed() then
    return
  end
  noticed = true
  util.notify(
    'agentdiff: attribution is "hooks" but no agent hook is installed, so nothing will be reviewed.\n'
      .. 'Run :Agentdiff hooks install, or set attribution = "writer" to review every change Neovim didn\'t make.',
    vim.log.levels.WARN
  )
end

---Forget that the notice was shown (tests).
function M.reset_notice()
  noticed = false
end

---@class AgentdiffHookStatus
---@field installed boolean
---@field where string[]      configuration files holding the hook
---@field last_report? integer wall-clock ms of its newest report for this project

---Per harness: where its hook is installed and when it last reported an edit
---for the current project. Shows it unless `opts.silent`.
---@param opts? { silent: boolean? }
---@return table<string, AgentdiffHookStatus>
function M.status(opts)
  local o = M.opts()
  local last = journal.last(store.dir_of(o.root))
  local res, lines = {}, { ("agentdiff hooks (attribution: %s)"):format(config.options.attribution) }
  for _, n in ipairs(harness.names()) do
    local st = harness.get(n).status(o)
    st.where = st.where or {}
    local entry = { installed = st.installed, where = st.where, last_report = last[n] }
    res[n] = entry
    local where = vim.tbl_map(function(f)
      return vim.fn.fnamemodify(f, ":~")
    end, st.where)
    local line = n
      .. ": "
      .. (st.installed and ("installed in " .. table.concat(where, ", ")) or "not installed")
    if entry.last_report then
      line = line .. " · last report " .. os.date("%Y-%m-%d %H:%M:%S", math.floor(entry.last_report / 1000))
    elseif st.installed then
      line = line .. " · no report yet for this project"
    end
    lines[#lines + 1] = line
  end
  if not (opts and opts.silent) then
    util.notify(table.concat(lines, "\n"))
  end
  return res
end

return M
