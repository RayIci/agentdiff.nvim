---Review state: per-file pending changes (baseline vs current content) and
---the session's pending list, recomputed by refresh(). Pending changes are
---always diff(B, current); buffers with unsaved edits are shown against a
---display baseline merge3(O, B, buffer).
---@class AgentdiffState
local M = {}

local events = require("agentdiff.core.events")
local merge = require("agentdiff.core.merge")
local session = require("agentdiff.core.session")
local txt = require("agentdiff.core.text")
local util = require("agentdiff.core.util")

local opt = txt.opt

---Recompute the review state of one path; nil when nothing is pending.
---@param s AgentdiffSession
---@param path string
---@return AgentdiffFile?
function M.compute(s, path)
  local B = opt(s.store:read("baseline", { path })[path])
  local D = util.read_file(session.abs(s, path))
  local buf = session.buf_of_rel(s, path)
  local modified = buf ~= nil and vim.bo[buf].modified
  if D == nil and not modified then
    buf = nil -- deleted on disk: the buffer is a leftover, review the deletion
  end
  local conflicted = s.conflicts[path] == true

  if txt.is_whole(s, B, D) then
    if B == D and not conflicted then
      return nil
    end
    ---@type AgentdiffFile
    return {
      path = path,
      status = conflicted and "conflicted"
        or (B == nil and "created")
        or (D == nil and "deleted")
        or "binary",
      whole = true,
      hunks = {},
      base = {},
      cur = {},
      added = 0,
      removed = 0,
      buf = buf,
    }
  end

  local cur, base
  if buf then
    cur = txt.buf_lines(buf)
    local bl = txt.disp(buf, B)
    local override = s.base_override[buf]
    if modified or override then
      local o = override or txt.disp(buf, opt(s.store:read("observed", { path })[path]))
      base = (merge.merge3(o, bl, cur))
    else
      base = bl
    end
  else
    cur = merge.lines(D)
    base = merge.lines(B)
  end

  local hunks = merge.diff(base, cur)
  if #hunks == 0 and not conflicted then
    return nil
  end
  -- Count real lines: a trailing "" only stands for the final newline.
  local function real(lines, lo, hi)
    local n = hi - lo
    if hi == #lines and hi > lo and lines[hi] == "" then
      n = n - 1
    end
    return n
  end
  local added, removed = 0, 0
  for _, h in ipairs(hunks) do
    added = added + real(cur, h.b_lo, h.b_hi)
    removed = removed + real(base, h.a_lo, h.a_hi)
  end
  ---@type AgentdiffFile
  return {
    path = path,
    status = conflicted and "conflicted"
      or (B == nil and "created")
      or (D == nil and "deleted")
      or "modified",
    whole = false,
    hunks = hunks,
    base = base,
    cur = cur,
    added = added,
    removed = removed,
    buf = buf,
  }
end

---@param s AgentdiffSession
local function rebuild_order(s)
  local order = vim.tbl_keys(s.files)
  table.sort(order)
  s.order = order
end

---Recompute review state: every pending path (paths = nil) or only some.
---@param s AgentdiffSession
---@param paths string[]?
function M.refresh(s, paths)
  if not s.ready then
    return
  end
  if paths == nil then
    local set = {}
    for _, c in ipairs(s.store:changes("baseline") or {}) do
      set[c.path] = true
    end
    for p in pairs(s.conflicts) do
      set[p] = true
    end
    for b in pairs(s.base_override) do
      local r = session.rel_of_buf(s, b)
      if r then
        set[r] = true
      end
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
        local r = session.rel_of_buf(s, b)
        if r then
          set[r] = true
        end
      end
    end
    s.files = {}
    for p in pairs(set) do
      s.files[p] = M.compute(s, p)
    end
  else
    for _, p in ipairs(paths) do
      s.files[p] = M.compute(s, p)
    end
  end
  rebuild_order(s)
  if paths == nil then
    s.refreshed = true
  end
  events.emit("refreshed", s, paths)
  events.changed(s)
end

return M
