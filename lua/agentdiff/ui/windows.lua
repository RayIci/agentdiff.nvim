---Picking the window a file opens in: never the panel, a side-by-side
---baseline, a file tree or any other special window.
---@class AgentdiffWindows
local M = {}

---An editing window: not floating, not pinned to its buffer (`winfixbuf`),
---showing a normal buffer (empty `buftype`).
---@param win integer?
---@return boolean
function M.is_editing(win)
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if
    vim.api.nvim_win_get_config(win).relative ~= ""
    or vim.wo[win].winfixbuf
    or vim.wo[win].previewwindow
  then
    return false
  end
  return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
end

---The previous window if it is an editing window, else the first editing
---window of the current tab, else nil.
---@return integer?
function M.main_win()
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if M.is_editing(prev) then
    return prev
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_editing(w) then
      return w
    end
  end
  return nil
end

---Make an editing window current: the current one if it is one, else
---main_win(), else a new split beside the current window (on the side away
---from the edge it sits at).
---@return integer win
function M.focus_editing()
  local cur = vim.api.nvim_get_current_win()
  if M.is_editing(cur) then
    return cur
  end
  local w = M.main_win()
  if not w then
    local pos = vim.api.nvim_win_get_position(cur)
    local vertical = vim.api.nvim_win_get_width(cur) < vim.o.columns
    local side
    if vertical then
      side = pos[2] == 0 and "right" or "left"
    else
      side = pos[1] <= 1 and "below" or "above"
    end
    w = vim.api.nvim_open_win(vim.api.nvim_create_buf(true, false), false, { split = side, win = cur })
    vim.bo[vim.api.nvim_win_get_buf(w)].bufhidden = "wipe"
  end
  vim.api.nvim_set_current_win(w)
  return w
end

return M
