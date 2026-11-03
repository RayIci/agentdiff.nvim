---Changed-files panel: every file with pending changes, its status and
---added/removed line counts, in navigation order.
---
---Panel keys: <CR>/o open at the first change · K keep file · U undo file ·
---gK keep all · gU undo all · R refresh · q close.
---@class AgentdiffPanel
local M = {}

local review_state = require("agentdiff.core.state")
local session = require("agentdiff.core.session")

---@type { buf: integer?, win: integer?, paths: table<integer, string>, au: integer? }
local state = { buf = nil, win = nil, paths = {}, au = nil }

local letters = { modified = "M", created = "A", deleted = "D", binary = "B", conflicted = "C" }

---What the panel's keys and summary call; injected by the entry point so the
---panel never reaches up into actions or the public API.
---@class AgentdiffPanelHandlers
---@field status fun(): string
---@field open fun(path: string)
---@field keep fun(opts: table)
---@field undo fun(opts: table)
---@field keep_all fun()
---@field undo_all fun()
---@field refresh fun()

---@type AgentdiffPanelHandlers
local handlers

---@param h AgentdiffPanelHandlers
function M.set_handlers(h)
  handlers = h
end

---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---Lines of the panel for the current session (also used by tests).
---@param s AgentdiffSession
---@return string[] lines
---@return table<integer, string> paths  line number → path
function M.lines(s)
  local lines, paths = {}, {}
  local status = handlers.status()
  lines[1] = "agentdiff  " .. (status ~= "" and status or "nothing pending")
  lines[2] = ""
  for _, p in ipairs(s.order) do
    local f = s.files[p]
    local counts = f.whole and "(whole file)" or ("+%d −%d"):format(f.added, f.removed)
    lines[#lines + 1] = ("%s %s  %s"):format(letters[f.status] or "?", p, counts)
    paths[#lines] = p
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "<CR> open  K/U keep/undo file  gK/gU all  q close"
  return lines, paths
end

function M.render()
  local s = session.get()
  if not s or not M.is_open() or not state.buf then
    return
  end
  local lines, paths = M.lines(s)
  state.paths = paths
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

---@return string?
local function path_at_cursor()
  return state.paths[vim.api.nvim_win_get_cursor(0)[1]]
end

---Run fn on the file under the cursor from the window the panel came from.
---@param fn fun(path: string)
local function on_file(fn)
  local p = path_at_cursor()
  if not p then
    return
  end
  vim.cmd.wincmd("p")
  if state.win and vim.api.nvim_get_current_win() == state.win then
    vim.cmd("rightbelow vsplit")
  end
  fn(p)
end

function M.open()
  local s = session.get()
  if not s then
    return
  end
  review_state.refresh(s)
  if M.is_open() then
    return M.render()
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "agentdiff"
  vim.cmd("topleft 40vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  for k, v in pairs({
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixwidth = true,
    wrap = false,
  }) do
    vim.wo[state.win][k] = v
  end
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, desc = desc })
  end
  map("<CR>", function()
    on_file(handlers.open)
  end, "Open file")
  map("o", function()
    on_file(handlers.open)
  end, "Open file")
  map("K", function()
    local p = path_at_cursor()
    if p then
      handlers.keep({ scope = "file", path = p })
    end
  end, "Keep file")
  map("U", function()
    local p = path_at_cursor()
    if p then
      handlers.undo({ scope = "file", path = p })
    end
  end, "Undo file")
  map("gK", function()
    handlers.keep_all()
  end, "Keep all")
  map("gU", function()
    handlers.undo_all()
  end, "Undo all")
  map("R", function()
    handlers.refresh()
  end, "Refresh")
  map("q", M.close, "Close")
  state.au = vim.api.nvim_create_autocmd("User", {
    pattern = "AgentdiffChanged",
    callback = M.render,
  })
  M.render()
  vim.api.nvim_win_set_cursor(state.win, { math.min(3, vim.api.nvim_buf_line_count(state.buf)), 0 })
end

function M.close()
  if state.au then
    pcall(vim.api.nvim_del_autocmd, state.au)
    state.au = nil
  end
  if M.is_open() then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win, state.buf, state.paths = nil, nil, {}
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

return M
