---Positions of pending changes: where a change is anchored in a buffer, the
---session-wide navigation order, the number of changes, and the change under
---(or nearest to) a row. Pure queries over the review state.
---@class AgentdiffPositions
local M = {}

---Row a hunk is anchored at in a buffer of `count` lines (0-based).
---@param h AgentdiffHunk
---@param count integer
---@return integer
function M.anchor_row(h, count)
  return math.max(0, math.min(h.b_lo, count - 1))
end

---Session-wide list of changes in navigation order.
---@param s AgentdiffSession
---@return { path: string, index: integer, row: integer }[]
function M.flatten(s)
  local out = {}
  for _, p in ipairs(s.order) do
    local f = s.files[p]
    if f.whole or #f.hunks == 0 then
      out[#out + 1] = { path = p, index = 0, row = 0 }
    else
      for i, h in ipairs(f.hunks) do
        out[#out + 1] = { path = p, index = i, row = h.b_lo }
      end
    end
  end
  return out
end

---Total number of pending changes.
---@param s AgentdiffSession
---@return integer
function M.count(s)
  local n = 0
  for _, p in ipairs(s.order) do
    local f = s.files[p]
    n = n + ((f.whole or #f.hunks == 0) and 1 or #f.hunks)
  end
  return n
end

---Index of the hunk under (or nearest to) a 0-based row.
---@param f AgentdiffFile
---@param row integer
---@param exact boolean  only a hunk under the row
---@return integer?
function M.hunk_at(f, row, exact)
  local best, best_d
  local count = #f.cur
  if count > 0 and f.cur[count] == "" then
    count = count - 1 -- the final-newline element is not a buffer line
  end
  for i, h in ipairs(f.hunks) do
    local lo = M.anchor_row(h, count)
    local hi = math.max(lo + 1, math.min(h.b_hi, count))
    if row >= lo and row < hi then
      return i
    end
    if not exact then
      local d = row < lo and (lo - row) or (row - hi + 1)
      if not best_d or d < best_d then
        best, best_d = i, d
      end
    end
  end
  return best
end

return M
