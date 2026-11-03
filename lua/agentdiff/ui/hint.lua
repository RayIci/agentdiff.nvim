---The hint on the pending change nearest the cursor: its position among all
---pending changes and the keys that keep or undo it.
---@class AgentdiffHint
local M = {}

local positions = require("agentdiff.core.positions")
local session = require("agentdiff.core.session")

M.ns = vim.api.nvim_create_namespace("agentdiff_hint")

---@param keys AgentdiffKeymaps|false
---@return string
local function key_hint(keys)
  if type(keys) ~= "table" then
    return ""
  end
  local parts = {}
  if keys.keep then
    parts[#parts + 1] = keys.keep .. " keep"
  end
  if keys.undo then
    parts[#parts + 1] = keys.undo .. " undo"
  end
  if #parts == 0 then
    return ""
  end
  return " · " .. table.concat(parts, " · ")
end

---Hint text for the change at a session-wide position.
---@param s AgentdiffSession
---@param pos integer
---@param conflicted boolean
---@return string
function M.text(s, pos, conflicted)
  local label = conflicted and "conflict" or "agent"
  return ("%s %d/%d%s"):format(label, pos, positions.count(s), key_hint(s.opts.keymaps))
end

---Place the hint on the change nearest the cursor of `win`.
---@param s AgentdiffSession
---@param win integer?
function M.draw(s, win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      vim.api.nvim_buf_clear_namespace(b, M.ns, 0, -1)
    end
  end
  if not s.opts.hint or s.overlay_hidden or s.views[buf] then
    return
  end
  local rel = session.rel_of_buf(s, buf)
  local f = rel and s.files[rel]
  if not f or f.buf ~= buf or f.whole or #f.hunks == 0 then
    return
  end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local i = positions.hunk_at(f, row, false)
  if not i then
    return
  end
  local pos = 0
  for n, e in ipairs(positions.flatten(s)) do
    if e.path == rel and e.index == i then
      pos = n
      break
    end
  end
  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_extmark(buf, M.ns, positions.anchor_row(f.hunks[i], count), 0, {
    virt_text = { { M.text(s, pos, f.status == "conflicted"), "AgentdiffHint" } },
    virt_text_pos = "right_align",
    priority = 130,
  })
end
---Keep the hint next to the cursor (the UI owns its own autocmds).
---@param s AgentdiffSession
function M.attach(s)
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufWinEnter", "WinEnter" }, {
    group = s.group,
    callback = function()
      M.draw(s)
    end,
  })
end

return M
