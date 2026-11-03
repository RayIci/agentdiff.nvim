---Keep and undo, for the change under the cursor, a line range, a file or
---every file. Keep and undo on a conflicted file resolve the conflict.
---
---Keep and undo take a scope ("hunk", "file", "all") and, for "hunk", an
---optional 1-based line range {l1, l2}: then only the lines of pending changes
---inside the range are kept or undone. A change's removed lines count as
---selected when the range starts at or above the change's first line.
---@class AgentdiffActionsReview
local M = {}

local baseline = require("agentdiff.core.baseline")
local buffers = require("agentdiff.editor.buffers")
local claims = require("agentdiff.core.claims")
local common = require("agentdiff.actions.common")
local merge = require("agentdiff.core.merge")
local positions = require("agentdiff.core.positions")
local resolve = require("agentdiff.actions.resolve")
local session = require("agentdiff.core.session")
local state = require("agentdiff.core.state")
local txt = require("agentdiff.core.text")
local util = require("agentdiff.core.util")

---@class AgentdiffSelection
---@field h AgentdiffHunk
---@field del boolean        removed lines selected
---@field lo integer         selected current-side rows [lo, hi)
---@field hi integer

---@param f AgentdiffFile
---@param range integer[]?
---@return AgentdiffSelection[]
local function select_hunks(f, range)
  local sel = {}
  if not range and vim.b.agentdiff_baseline_of then
    -- In the side-by-side baseline window the cursor is on the baseline side.
    local row = common.cursor_row()
    for _, h in ipairs(f.hunks) do
      if row >= h.a_lo and row < math.max(h.a_hi, h.a_lo + 1) then
        return { { h = h, del = true, lo = h.b_lo, hi = h.b_hi } }
      end
    end
    return sel
  end
  if not range then
    local i = positions.hunk_at(f, common.cursor_row(), true)
    if i then
      local h = f.hunks[i]
      sel[1] = { h = h, del = true, lo = h.b_lo, hi = h.b_hi }
    end
    return sel
  end
  local r1, r2 = range[1] - 1, range[2] -- rows [r1, r2)
  local nlines = #f.cur
  if nlines > 0 and f.cur[nlines] == "" then
    nlines = nlines - 1
  end
  for _, h in ipairs(f.hunks) do
    local lo, hi = math.max(h.b_lo, r1), math.min(h.b_hi, r2)
    -- Removed lines are drawn above the anchor row: selected when the range
    -- covers that row and starts at or above it.
    local anchor = positions.anchor_row(h, nlines)
    local del = h.a_hi > h.a_lo and r1 <= anchor and anchor < r2
    if hi > lo or del then
      sel[#sel + 1] = { h = h, del = del, lo = math.max(lo, h.b_lo), hi = math.max(hi, math.max(lo, h.b_lo)) }
    end
  end
  return sel
end

---Baseline lines after keeping the selections.
---@param f AgentdiffFile
---@param sels AgentdiffSelection[]
---@return string[]
local function kept_base(f, sels)
  local base = f.base
  for i = #sels, 1, -1 do
    local x = sels[i]
    local repl = x.del and {} or merge.slice(f.base, x.h.a_lo, x.h.a_hi)
    vim.list_extend(repl, merge.slice(f.cur, x.lo, x.hi))
    base = merge.splice(base, x.h.a_lo, x.h.a_hi, repl)
  end
  return base
end

---Current lines after undoing the selections.
---@param f AgentdiffFile
---@param sels AgentdiffSelection[]
---@return string[]
local function undone_cur(f, sels)
  local cur = f.cur
  for i = #sels, 1, -1 do
    local x = sels[i]
    local repl = x.del and merge.slice(f.base, x.h.a_lo, x.h.a_hi) or {}
    vim.list_extend(repl, merge.slice(f.cur, x.h.b_lo, x.lo))
    vim.list_extend(repl, merge.slice(f.cur, x.hi, x.h.b_hi))
    cur = merge.splice(cur, x.h.b_lo, x.h.b_hi, repl)
  end
  return cur
end

---@param s AgentdiffSession
---@param rel string
local function disk_text(s, rel)
  return util.read_file(session.abs(s, rel))
end

---Write the baseline from new display-space baseline lines of a file.
---@param s AgentdiffSession
---@param f AgentdiffFile
---@param new_base string[]
local function write_base(s, f, new_base)
  local B = s.store:read("baseline", { f.path })[f.path] or nil
  local text
  if f.buf then
    local bl = txt.disp(f.buf, B)
    text = txt.undisp(f.buf, (merge.merge3(f.base, bl, new_base)))
  else
    text = merge.join(new_base)
  end
  if B == nil and f.status == "created" and #new_base == 0 then
    text = nil
  end
  baseline.set_baseline(s, f.path, text)
end

---@param s AgentdiffSession
---@param rel string
---@return integer
local function load_hidden(s, rel)
  local b = vim.fn.bufadd(session.abs(s, rel))
  if not vim.api.nvim_buf_is_loaded(b) then
    vim.bo[b].buflisted = false
    vim.fn.bufload(b)
  end
  return b
end

---Restore the baseline of a whole file on disk (created/deleted/binary files).
---@param s AgentdiffSession
---@param rel string
local function restore_whole(s, rel)
  local B = s.store:read("baseline", { rel })[rel] or nil
  claims.add(s.store, { rel })
  local buf = session.buf_of_rel(s, rel)
  if B == nil then
    os.remove(session.abs(s, rel))
    if buf then
      buffers.wipe(buf)
    end
  else
    util.write_file(session.abs(s, rel), B)
  end
  baseline.process(s, { rel }, "user")
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.cmd.checktime, buf)
  end
end

---@param s AgentdiffSession
---@param rel string
---@param f AgentdiffFile
---@param opts AgentdiffActionOpts
---@return boolean changed
local function keep_one(s, rel, f, opts)
  if f.whole or f.status == "deleted" or (f.status == "created" and opts.scope ~= "hunk") then
    local D = disk_text(s, rel)
    baseline.set_baseline(s, rel, D)
    if D == nil then
      local buf = session.buf_of_rel(s, rel)
      if buf and not vim.bo[buf].modified then
        buffers.wipe(buf)
      end
    end
    s.conflicts[rel] = nil
    return true
  end
  local sels
  if opts.scope == "hunk" then
    sels = select_hunks(f, opts.range)
    if #sels == 0 then
      return false
    end
  else
    sels = {}
    for _, h in ipairs(f.hunks) do
      sels[#sels + 1] = { h = h, del = true, lo = h.b_lo, hi = h.b_hi }
    end
  end
  write_base(s, f, kept_base(f, sels))
  return true
end

---@param s AgentdiffSession
---@param rel string
---@param f AgentdiffFile
---@param opts AgentdiffActionOpts
---@return boolean changed
local function undo_one(s, rel, f, opts)
  local whole_scope = opts.scope ~= "hunk" or (not opts.range and #f.hunks == 1)
  if f.whole or f.status == "deleted" or (f.status == "created" and whole_scope) then
    restore_whole(s, rel)
    s.conflicts[rel] = nil
    return true
  end
  if not f.buf then
    load_hidden(s, rel)
    local loaded = state.compute(s, rel)
    if not loaded then
      return false
    end
    f = loaded
  end
  local buf = assert(f.buf)
  local sels
  if opts.scope == "hunk" then
    sels = select_hunks(f, opts.range)
    if #sels == 0 then
      return false
    end
  else
    sels = {}
    for _, h in ipairs(f.hunks) do
      sels[#sels + 1] = { h = h, del = true, lo = h.b_lo, hi = h.b_hi }
    end
  end
  local was_modified = vim.bo[buf].modified
  local before = txt.buf_lines(buf)
  local seq_before = buffers.undo_seq(buf)
  buffers.set_lines(buf, undone_cur(f, sels))
  buffers.record_undo(s, buf, { seq_before = seq_before, seq_after = buffers.undo_seq(buf), before = before })
  if not was_modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent keepalt keepjumps update")
    end)
  end
  return true
end

---@param what string
---@return boolean
local function confirm_all(s, what, opts)
  if opts.force or not s.opts.confirm then
    return true
  end
  local n = positions.count(s)
  return vim.fn.confirm(("%s all %d pending changes in %d files?"):format(what, n, #s.order), "&Yes\n&No", 2)
    == 1
end

---@param kind "keep"|"undo"
---@param opts AgentdiffActionOpts?
local function act(kind, opts)
  opts = opts or {}
  opts.scope = opts.scope or "hunk"
  local s = common.active()
  if not s then
    return
  end
  local fn = kind == "keep" and keep_one or undo_one
  if opts.scope == "all" then
    state.refresh(s)
    if #s.order == 0 then
      return util.notify("agentdiff: nothing pending")
    end
    if not confirm_all(s, kind == "keep" and "Keep" or "Undo", opts) then
      return
    end
    for _, p in ipairs(vim.list_extend({}, s.order)) do
      if s.conflicts[p] then
        resolve.resolve(kind == "keep" and "accept" or "mine", p)
      else
        local f = state.compute(s, p)
        if f then
          fn(s, p, f, { scope = "file" })
        end
      end
    end
    state.refresh(s)
    return
  end
  local rel, f = common.target(s, opts.path)
  if not rel or not f then
    return util.notify("agentdiff: no pending change here")
  end
  if s.conflicts[rel] then
    -- a conflict is resolved as a whole file: keep = accept the agent's
    -- version, undo = keep yours
    return resolve.resolve(kind == "keep" and "accept" or "mine", rel)
  end
  if not fn(s, rel, f, opts) then
    return util.notify("agentdiff: no pending change under the cursor")
  end
  state.refresh(s, { rel })
end

---@param opts AgentdiffActionOpts?
function M.keep(opts)
  act("keep", opts)
end

---@param opts AgentdiffActionOpts?
function M.undo(opts)
  act("undo", opts)
end

return M
