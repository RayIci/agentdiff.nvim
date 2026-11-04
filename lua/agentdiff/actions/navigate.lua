---Navigation between pending changes and changed files.
---@class AgentdiffActionsNavigate
local M = {}

local common = require("agentdiff.actions.common")
local hint = require("agentdiff.ui.hint")
local windows = require("agentdiff.ui.windows")
local positions = require("agentdiff.core.positions")
local session = require("agentdiff.core.session")
local state = require("agentdiff.core.state")
local util = require("agentdiff.core.util")

---@param s AgentdiffSession
---@param rel string
---@param row integer 0-based
local function jump(s, rel, row)
  -- never edit in the panel or another special window
  windows.focus_editing()
  local cur = session.rel_of_buf(s, vim.api.nvim_get_current_buf())
  if cur ~= rel then
    vim.cmd.edit(vim.fn.fnameescape(session.abs(s, rel)))
  end
  local count = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(row + 1, count)), 0 })
  hint.draw(s)
end

---@param dir 1|-1
---@param by_file boolean
local function move(dir, by_file)
  local s = common.active()
  if not s then
    return
  end
  state.refresh(s)
  local entries = positions.flatten(s)
  if #entries == 0 then
    return util.notify("agentdiff: nothing pending")
  end
  if by_file then
    local seen, files = {}, {}
    for _, e in ipairs(entries) do
      if not seen[e.path] then
        seen[e.path] = true
        files[#files + 1] = e
      end
    end
    entries = files
  end
  local cur = session.rel_of_buf(s, vim.api.nvim_get_current_buf()) or ""
  local row = common.cursor_row()
  local function after(e)
    if by_file then
      return e.path > cur
    end
    return e.path > cur or (e.path == cur and e.row > row)
  end
  local function before(e)
    if by_file then
      return e.path < cur
    end
    return e.path < cur or (e.path == cur and e.row < row)
  end
  local pick
  if dir == 1 then
    for _, e in ipairs(entries) do
      if after(e) then
        pick = e
        break
      end
    end
    if not pick then
      pick = entries[1]
      util.notify("agentdiff: wrapped to the first change")
    end
  else
    for i = #entries, 1, -1 do
      if before(entries[i]) then
        pick = entries[i]
        break
      end
    end
    if not pick then
      pick = entries[#entries]
      util.notify("agentdiff: wrapped to the last change")
    end
  end
  jump(s, pick.path, pick.row)
end

function M.next()
  move(1, false)
end

function M.prev()
  move(-1, false)
end

function M.next_file()
  move(1, true)
end

function M.prev_file()
  move(-1, true)
end

---Open a pending file at its first change.
---@param rel string
function M.open(rel)
  local s = common.active()
  if not s then
    return
  end
  local f = s.files[rel] or state.compute(s, rel)
  jump(s, rel, f and f.hunks[1] and f.hunks[1].b_lo or 0)
end

return M
