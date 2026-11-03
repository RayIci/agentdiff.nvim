---When to look: while Neovim is focused, a timer polls every `poll_interval`
---ms (two stat-only git queries against the observed index); polls also run on
---focus, BufEnter and around shell commands. Each poll asks the active
---attribution mode who changed what, then applies the author rule.
---@class AgentdiffPoller
local M = {}

local attribution = require("agentdiff.attribution")
local baseline = require("agentdiff.core.baseline")
local git = require("agentdiff.detect.git")
local session = require("agentdiff.core.session")
local shell = require("agentdiff.attribution.shell")
local state = require("agentdiff.core.state")
local util = require("agentdiff.core.util")

local uv = vim.uv

---@type uv.uv_timer_t?
local timer = nil
local running = false
local focused = true
---@type uv.uv_timer_t?
local confirm_timer = nil

---Reload loaded, unmodified buffers of changed paths (FileChangedShell does
---the per-buffer work, including merging into modified buffers).
---@param s AgentdiffSession
---@param paths string[]
local function sync_buffers(s, paths)
  for _, p in ipairs(paths) do
    local b = session.buf_of_rel(s, p)
    if b then
      pcall(vim.cmd.checktime, b)
    end
  end
end

---Attribute and process a list of changes against the observed index.
---@param s AgentdiffSession
---@param changes AgentdiffChange[]
---@param mode "poll"|"agent"|"user"  poll = normal attribution; agent/user force the author
---@return boolean need_confirm
local function handle(s, changes, mode)
  local moved = git.observe(s)
  local r = attribution.active(s).classify(s, changes, {
    mode = mode,
    now = util.now_ms(),
    guard_moved = moved.guard_moved,
    produced = function(paths)
      return git.git_produced(s, paths)
    end,
    discarded = function(paths)
      return git.discarded(s, paths)
    end,
  })
  baseline.process(s, r.user, "user")
  baseline.process(s, r.agent, "agent")
  if #r.user > 0 or #r.agent > 0 then
    local all = vim.list_extend(vim.list_extend({}, r.user), r.agent)
    sync_buffers(s, all)
    state.refresh(s)
  end
  git.after_poll(s, moved)
  return #r.wait > 0
end

---@param s AgentdiffSession
local function schedule_confirm(s)
  if confirm_timer then
    return
  end
  local t = assert(uv.new_timer())
  confirm_timer = t
  t:start(s.opts.settle, 0, function()
    t:close()
    confirm_timer = nil
    vim.schedule(M.poll)
  end)
end

---Asynchronous poll (the timer's work).
function M.poll()
  local s = session.get()
  if not s or not s.ready or running then
    return
  end
  running = true
  s.store:changes("observed", function(changes)
    running = false
    if session.get() ~= s then
      return
    end
    local ok, need = pcall(handle, s, changes, "poll")
    if not ok then
      util.notify("agentdiff: " .. tostring(need), vim.log.levels.ERROR)
    elseif need then
      schedule_confirm(s)
    end
  end)
end

---Synchronous detection.
---  mode "poll"  normal attribution (settle respected unless opts.settle == false)
---  mode "agent" every unclaimed change is the agent's (before a shell command)
---  mode "user"  every change is the user's (right after a shell command)
---@param mode? "poll"|"agent"|"user"
---@param opts? { settle: boolean? }
function M.now(mode, opts)
  local s = session.get()
  if not s or not s.ready then
    return
  end
  local saved = s.opts.settle
  if opts and opts.settle == false then
    s.opts.settle = 0
  end
  local ok, err = pcall(function()
    local need = handle(s, s.store:changes("observed") or {}, mode or "poll")
    if need then
      schedule_confirm(s)
    end
  end)
  s.opts.settle = saved
  if not ok then
    error(err, 0)
  end
end

---@param s AgentdiffSession
local function start_timer(s)
  if s.opts.poll_interval <= 0 then
    return
  end
  if not timer then
    timer = assert(uv.new_timer())
  end
  local t = timer
  t:start(0, s.opts.poll_interval, function()
    vim.schedule(M.poll)
  end)
end

local function stop_timer()
  if timer then
    timer:stop()
  end
end

---@param s AgentdiffSession
function M.start(s)
  git.start(s)
  local g = s.group
  vim.api.nvim_create_autocmd("FocusLost", {
    group = g,
    callback = function()
      focused = false
      stop_timer()
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = g,
    callback = function()
      focused = true
      start_timer(s)
    end,
  })
  local last_enter = 0
  vim.api.nvim_create_autocmd("BufEnter", {
    group = g,
    callback = function()
      local now = uv.now()
      if now - last_enter > 200 then
        last_enter = now
        M.poll()
      end
    end,
  })
  -- Shell commands from Neovim: settle what's pending first, then claim
  -- whatever the command changed.
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = g,
    callback = function()
      if vim.v.event.abort or vim.fn.getcmdtype() ~= ":" then
        return
      end
      if shell.is_shell_cmdline(vim.fn.getcmdline()) then
        pcall(M.now, "agent")
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "ShellCmdPost", "ShellFilterPost" }, {
    group = g,
    callback = function()
      pcall(M.now, "user")
    end,
  })
  if focused then
    start_timer(s)
  end
end

function M.stop()
  stop_timer()
  if timer and not timer:is_closing() then
    timer:close()
  end
  timer = nil
  if confirm_timer and not confirm_timer:is_closing() then
    confirm_timer:close()
  end
  confirm_timer = nil
  attribution.reset()
  git.stop()
  running = false
  focused = true
end

return M
