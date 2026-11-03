---The "hooks" attribution mode: a disk change is the agent's only when an
---agent hook reported that file (see core/journal and bin/agentdiff-hook.lua).
---Neovim's own writes and claims are the user's as in the writer mode; every
---other change is the user's too, folded into the baseline without review.
---
---A report matches a change when it was made within `report_window` ms of the
---file's modification time, so edits made while Neovim was unfocused or not
---running are still recognised, and a stale report (a tool call that failed)
---never attributes a later, unrelated change. A matched report is consumed: it
---covers one change.
---
---An unreported change younger than `hook_wait` ms is looked at again first,
---for a hook that runs only after the tool call ("post").
---@class AgentdiffHooksMode: AgentdiffAttribution
local M = {}
M.name = "hooks"

local claims = require("agentdiff.core.claims")
local journal = require("agentdiff.core.journal")
local session = require("agentdiff.core.session")

local uv = vim.uv

M.report_window = 10000
M.hook_wait = 1500
---How often old reports are deleted.
M.gc_interval = 60000

---@type table<string, integer>  deleted path → first time it was seen
local suspects = {}
local last_gc = 0

function M.reset()
  suspects = {}
  last_gc = 0
end

---Modification time of a project file in ms, nil when it doesn't exist.
---@param s AgentdiffSession
---@param rel string
---@return integer?
local function mtime(s, rel)
  local st = uv.fs_stat(s.root .. "/" .. rel)
  return st and (st.mtime.sec * 1000 + math.floor(st.mtime.nsec / 1e6)) or nil
end

---@param times integer[]?
---@param at integer?  the change's mtime; nil for a deletion (any report counts)
---@return boolean
local function matches(times, at)
  for _, t in ipairs(times or {}) do
    if not at or math.abs(at - t) <= M.report_window then
      return true
    end
  end
  return false
end

---@param s AgentdiffSession
---@param changes AgentdiffChange[]
---@param ctx AgentdiffAttributionCtx
---@return AgentdiffAttributionResult
function M.classify(s, changes, ctx)
  local dir = s.store.dir
  if ctx.now - last_gc > M.gc_interval then
    last_gc = ctx.now
    pcall(journal.gc, dir, ctx.now)
  end
  local times = nil
  local users, agents, waits = {}, {}, {}
  local seen = {}
  for _, c in ipairs(changes) do
    local p = c.path
    seen[p] = true
    if not session.reviewable(s, p) or s.writing[p] then
      -- not reviewed, or Neovim is writing it (BufWritePost handles it)
    elseif ctx.mode == "user" or claims.claimed(s.store, p, s.opts.claim_ttl) then
      users[#users + 1] = p
    else
      times = times or journal.times(dir)
      local at = mtime(s, p)
      if matches(times[p], at) then
        agents[#agents + 1] = p
      elseif ctx.mode == "poll" and s.opts.settle > 0 and at and ctx.now - at < M.hook_wait then
        waits[#waits + 1] = p
      elseif
        ctx.mode == "poll"
        and s.opts.settle > 0
        and not at
        and ctx.now - (suspects[p] or ctx.now) < M.hook_wait
      then
        suspects[p] = suspects[p] or ctx.now
        waits[#waits + 1] = p
      else
        users[#users + 1] = p
      end
    end
  end
  for p in pairs(suspects) do
    if not seen[p] then
      suspects[p] = nil
    end
  end
  for _, p in ipairs(users) do
    suspects[p] = nil
  end
  for _, p in ipairs(agents) do
    suspects[p] = nil
  end
  journal.take(dir, agents, ctx.now)
  return { agent = agents, user = users, wait = waits }
end

return M
