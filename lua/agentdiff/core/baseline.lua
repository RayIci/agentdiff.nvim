---Baseline updates: the author rule applied to disk changes, keeping staged
---changes, and direct baseline writes (keep).
---
---The invariant: a file's pending changes are diff(B, current), where B is the
---baseline. Every disk change has an author:
---  agent  O := disk               (B unchanged, so the change is now pending)
---  user   B := merge3(O, B, disk) (your delta lands in B too), then O := disk
---merge3 resolves overlaps to B, so a user edit touching a pending change only
---lands in the current content and becomes part of that change.
---@class AgentdiffBaseline
local M = {}

local claims = require("agentdiff.core.claims")
local merge = require("agentdiff.core.merge")
local session = require("agentdiff.core.session")
local txt = require("agentdiff.core.text")
local util = require("agentdiff.core.util")

local opt = txt.opt

---Apply the author rule to disk changes of `paths`.
---@param s AgentdiffSession
---@param paths string[]
---@param author "agent"|"user"
function M.process(s, paths, author)
  if #paths == 0 then
    return
  end
  s.store:locked(function()
    if author == "agent" then
      s.store:adopt("observed", paths)
      return
    end
    local O = s.store:read("observed", paths)
    local B = s.store:read("baseline", paths)
    local bwrites, owrites = {}, {}
    for _, p in ipairs(paths) do
      local D = util.read_file(session.abs(s, p))
      local o, b = opt(O[p]), opt(B[p])
      local nb
      if D == nil then
        nb = nil -- the user deleted it
      elseif o == nil then
        nb = D -- the user created (or re-created) it
      elseif txt.is_whole(s, o, b, D) then
        nb = D
      else
        local buf = session.buf_of_rel(s, p)
        local base_lines = merge.lines(o)
        if buf and s.base_override[buf] then
          base_lines = merge.lines(txt.undisp(buf, s.base_override[buf]))
        end
        local merged = merge.merge3(base_lines, merge.lines(b), merge.lines(D))
        if b == nil and #merged == 0 then
          nb = nil -- still an agent-created file pending review
        else
          nb = merge.join(merged)
        end
      end
      if nb ~= b then
        bwrites[#bwrites + 1] = { path = p, text = nb }
      end
      owrites[#owrites + 1] = { path = p, text = D }
    end
    s.store:write("baseline", bwrites)
    s.store:write("observed", owrites)
    s.store:refresh("observed")
  end)
  -- A claim covers one change: consume it, so a later agent edit of the same
  -- path is the agent's again.
  for _, p in ipairs(paths) do
    claims.release(s.store, p)
  end
end

---Keep the pending changes that are staged in the project's index (VS Code:
---staging keeps pending edits). A pending hunk B→disk is staged when no hunk
---of diff(index, disk) overlaps or touches its region of the disk content;
---staged hunks are applied to B. Unstaged parts stay pending; nothing is ever
---made pending again by this (unstaging is not an undo).
---@param s AgentdiffSession
---@param paths string[]           pending project-relative paths
---@param staged table<string, string|false>  index content per path
---@param head table<string, string|false>    HEAD content per path (for staged deletions)
---@param ever table<string, boolean>           paths with git history (for committed deletions)
---@return boolean changed
function M.keep_staged(s, paths, staged, head, ever)
  local changed = false
  local B = s.store:read("baseline", paths)
  for _, p in ipairs(paths) do
    local b = opt(B[p])
    local I = opt(staged[p])
    local D = util.read_file(session.abs(s, p))
    local nb = b
    if D == nil then
      -- a deletion is staged (or committed) when the index no longer has a
      -- file that HEAD has, or that was tracked at some point
      if I == nil and (head[p] or ever[p]) then
        nb = nil
      end
    elseif I ~= nil then
      if txt.is_whole(s, b, D, I) then
        if I == D then
          nb = D
        end
      else
        local bl, dl = merge.lines(b), merge.lines(D)
        local unstaged = merge.diff(merge.lines(I), dl)
        local hunks = merge.diff(bl, dl)
        local base = bl
        for i = #hunks, 1, -1 do
          local h = hunks[i]
          local touched = false
          for _, g in ipairs(unstaged) do
            if g.b_lo <= h.b_hi and h.b_lo <= g.b_hi then
              touched = true
              break
            end
          end
          if not touched then
            base = merge.splice(base, h.a_lo, h.a_hi, merge.slice(dl, h.b_lo, h.b_hi))
          end
        end
        nb = (b == nil and #base == 0) and nil or merge.join(base)
      end
    end
    if nb ~= b then
      M.set_baseline(s, p, nb)
      changed = true
    end
  end
  return changed
end

---Set B for one path (keep), from display-space lines of the given buffer.
---@param s AgentdiffSession
---@param path string
---@param text string?
function M.set_baseline(s, path, text)
  s.store:locked(function()
    s.store:write("baseline", { { path = path, text = text } })
    s.store:refresh("baseline")
  end)
end

return M
