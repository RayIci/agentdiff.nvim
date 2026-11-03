---The "writer" attribution mode: Neovim's own writes and claimed paths are the
---user's; everything else that changed on disk is the agent's, except what git
---itself produced (checkout, pull, stash…) and discards toward HEAD.
---
---An unclaimed change is confirmed as the agent's only when it is still
---unclaimed `settle` ms after it was first seen, which gives another Neovim
---instance time to claim its own write.
---@class AgentdiffWriterMode: AgentdiffAttribution
local M = {}
M.name = "writer"

local claims = require("agentdiff.core.claims")
local session = require("agentdiff.core.session")

---@type table<string, integer>  path → first time an unclaimed change was seen
local suspects = {}

function M.reset()
  suspects = {}
end

---@param s AgentdiffSession
---@param changes AgentdiffChange[]
---@param ctx AgentdiffAttributionCtx
---@return AgentdiffAttributionResult
function M.classify(s, changes, ctx)
  local ttl = s.opts.claim_ttl
  local users, agents, waits, candidates = {}, {}, {}, {}
  local seen = {}
  for _, c in ipairs(changes) do
    local p = c.path
    seen[p] = true
    if not session.reviewable(s, p) then
      -- never reviewed (e.g. a stale entry under .git/): nothing to attribute
    elseif s.writing[p] then
      -- Neovim is writing it: BufWritePost processes it synchronously.
    elseif ctx.mode == "user" or claims.claimed(s.store, p, ttl) then
      users[#users + 1] = p
    elseif ctx.mode == "agent" then
      agents[#agents + 1] = p
    else
      candidates[#candidates + 1] = p
    end
  end

  local produced = ctx.guard_moved and ctx.produced(candidates) or {}
  local rest = {}
  for _, p in ipairs(candidates) do
    if not produced[p] then
      rest[#rest + 1] = p
    end
  end
  local reverted = ctx.discarded(rest)
  for _, p in ipairs(candidates) do
    if produced[p] or reverted[p] then
      users[#users + 1] = p
    elseif s.opts.settle > 0 and (not suspects[p] or ctx.now - suspects[p] < s.opts.settle) then
      suspects[p] = suspects[p] or ctx.now
      waits[#waits + 1] = p
    else
      agents[#agents + 1] = p
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
  return { agent = agents, user = users, wait = waits }
end

return M
