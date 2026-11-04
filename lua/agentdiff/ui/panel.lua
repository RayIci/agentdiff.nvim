---Changed-files panel: every file with pending changes, as a tree of folders
---and files or as a flat list, with status, added/removed counts and icons.
---
---Panel keys: <CR>/o open the file at its first change (or fold a folder) ·
---K/U keep/undo the file · gK/gU keep/undo all · t tree ↔ list · R refresh ·
---? keys · q close.
---
---The panel window is pinned to the panel buffer (`winfixbuf`); files always
---open in an editing window (see ui/windows).
---@class AgentdiffPanel
local M = {}

local config = require("agentdiff.config")
local icons = require("agentdiff.ui.icons")
local review_state = require("agentdiff.core.state")
local session = require("agentdiff.core.session")
local windows = require("agentdiff.ui.windows")

M.ns = vim.api.nvim_create_namespace("agentdiff_panel")

---@alias AgentdiffPanelView "tree"|"list"

---@class AgentdiffPanelRow
---@field kind "title"|"blank"|"dir"|"file"|"help"
---@field text string
---@field path? string   the file of a file row
---@field dir? string    the folder of a folder row
---@field marks { [1]: integer, [2]: integer, [3]: string }[]  byte start, end, highlight group
---@field right { [1]: string, [2]: string }[]                 right-aligned chunks

---@class AgentdiffPanelState
---@field buf integer?
---@field win integer?
---@field view AgentdiffPanelView?
---@field rows AgentdiffPanelRow[]
---@field group integer?
---@field help boolean

---@type AgentdiffPanelState
local state = { rows = {}, help = false }

---The view used by panel() without a view: the last one shown.
---@type AgentdiffPanelView?
local last_view = nil

---Folders collapsed by the user (by path), kept while Neovim runs.
---@type table<string, boolean>
local collapsed = {}

local letters = { modified = "M", created = "A", deleted = "D", binary = "B", conflicted = "C" }
local status_hl = {
  modified = "AgentdiffPanelModified",
  created = "AgentdiffPanelCreated",
  deleted = "AgentdiffPanelDeleted",
  binary = "AgentdiffPanelBinary",
  conflicted = "AgentdiffPanelConflicted",
}

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

---The view the panel shows, nil when closed.
---@return AgentdiffPanelView?
function M.view()
  return M.is_open() and state.view or nil
end

---The panel's window, nil when closed.
---@return integer?
function M.win()
  return M.is_open() and state.win or nil
end

-- Rows ------------------------------------------------------------------------

---@return AgentdiffPanelOptions
local function popts()
  return config.options.panel
end

---Right-aligned counts of a file or a folder.
---@param added integer
---@param removed integer
---@param whole boolean?
---@param dim boolean?  folders: one dim group
---@return { [1]: string, [2]: string }[]
local function counts(added, removed, whole, dim)
  if whole then
    return { { "whole file", "AgentdiffPanelCount" } }
  end
  local out = {}
  if added > 0 then
    out[#out + 1] = { "+" .. added, dim and "AgentdiffPanelCount" or "AgentdiffPanelAdded" }
  end
  if removed > 0 then
    if #out > 0 then
      out[#out + 1] = { " ", "Normal" }
    end
    out[#out + 1] = { "−" .. removed, dim and "AgentdiffPanelCount" or "AgentdiffPanelRemoved" }
  end
  return out
end

---Row builder: text pieces with their highlight groups.
---@param kind string
---@return AgentdiffPanelRow
---@return fun(s: string, hl: string?)
local function row(kind)
  ---@type AgentdiffPanelRow
  local r = { kind = kind, text = "", marks = {}, right = {} }
  local function add(s, hl)
    if hl and s ~= "" then
      r.marks[#r.marks + 1] = { #r.text, #r.text + #s, hl }
    end
    r.text = r.text .. s
  end
  return r, add
end

---@param f AgentdiffFile
---@return { [1]: string, [2]: string }[]
local function file_right(f)
  local right = counts(f.added, f.removed, f.whole)
  if #right > 0 then
    right[#right + 1] = { "  ", "Normal" }
  end
  right[#right + 1] = { letters[f.status] or "?", status_hl[f.status] or "AgentdiffPanelCount" }
  return right
end

---@param f AgentdiffFile
---@param indent string
---@param name string
---@param with_icons boolean
---@return AgentdiffPanelRow
local function file_row(f, indent, name, with_icons)
  local r, add = row("file")
  r.path = f.path
  add(indent)
  local icon, icon_hl = icons.file(name, with_icons)
  if icon then
    add(icon, icon_hl or "AgentdiffPanelFileIcon")
    add(" ")
  end
  add(name, f.status == "deleted" and "AgentdiffPanelDeletedName" or nil)
  r.right = file_right(f)
  return r
end

---@class AgentdiffPanelNode
---@field name string
---@field path string
---@field dirs table<string, AgentdiffPanelNode>
---@field files string[]
---@field added integer
---@field removed integer

---@param s AgentdiffSession
---@return AgentdiffPanelNode
local function build_tree(s)
  ---@type AgentdiffPanelNode
  local root = { name = "", path = "", dirs = {}, files = {}, added = 0, removed = 0 }
  for _, p in ipairs(s.order) do
    local f = s.files[p]
    local parts = vim.split(p, "/", { plain = true })
    local node = root
    for i = 1, #parts - 1 do
      local key = parts[i]
      if not node.dirs[key] then
        node.dirs[key] = {
          name = key,
          path = table.concat(parts, "/", 1, i),
          dirs = {},
          files = {},
          added = 0,
          removed = 0,
        }
      end
      node = node.dirs[key]
      node.added, node.removed = node.added + f.added, node.removed + f.removed
    end
    table.insert(node.files, p)
  end
  return root
end

---@param s AgentdiffSession
---@param node AgentdiffPanelNode
---@param depth integer
---@param rows AgentdiffPanelRow[]
---@param with_icons boolean
local function tree_rows(s, node, depth, rows, with_icons)
  local indent = " " .. string.rep("  ", depth)
  local names = vim.tbl_keys(node.dirs)
  table.sort(names)
  for _, n in ipairs(names) do
    local d = node.dirs[n]
    local label = d.name
    -- compact a chain of folders that each hold only one folder
    while #d.files == 0 and vim.tbl_count(d.dirs) == 1 do
      local _, only = next(d.dirs) ---@cast only AgentdiffPanelNode
      label = label .. "/" .. only.name
      d = only
    end
    local open = not collapsed[d.path]
    local r, add = row("dir")
    r.dir = d.path
    add(indent)
    local fold, icon = icons.dir(open, with_icons)
    add(fold, "AgentdiffPanelFold")
    add(" ")
    if icon then
      add(icon, "AgentdiffPanelDirIcon")
      add(" ")
    end
    add(label, "AgentdiffPanelDir")
    r.right = counts(d.added, d.removed, false, true)
    rows[#rows + 1] = r
    if open then
      tree_rows(s, d, depth + 1, rows, with_icons)
    end
  end
  local files = vim.deepcopy(node.files)
  table.sort(files, function(a, b)
    return vim.fs.basename(a) < vim.fs.basename(b)
  end)
  for _, p in ipairs(files) do
    -- files line up with folder names (past the fold marker)
    rows[#rows + 1] = file_row(s.files[p], indent .. "  ", vim.fs.basename(p), with_icons)
  end
end

---@param s AgentdiffSession
---@param rows AgentdiffPanelRow[]
---@param with_icons boolean
local function list_rows(s, rows, with_icons)
  for _, p in ipairs(s.order) do
    local r = file_row(s.files[p], " ", vim.fs.basename(p), with_icons)
    local dir = vim.fs.dirname(p)
    if dir ~= "." and dir ~= "" then
      local start = #r.text + 2
      r.text = r.text .. "  " .. dir
      r.marks[#r.marks + 1] = { start, #r.text, "AgentdiffPanelPath" }
    end
    rows[#rows + 1] = r
  end
end

local help_keys = {
  { "<CR>/o", "open · fold" },
  { "K/U", "keep/undo file" },
  { "gK/gU", "keep/undo all" },
  { "t", "tree/list" },
  { "R", "refresh" },
  { "q", "close" },
}

---Rows of the panel for the current session (also used by tests).
---@param s AgentdiffSession
---@param view AgentdiffPanelView
---@param help? boolean  show every key
---@return AgentdiffPanelRow[]
function M.rows(s, view, help)
  local with_icons = popts().icons
  local rows = {}
  local title, add = row("title")
  add(" ")
  if with_icons then
    add(icons.glyphs.title, "AgentdiffPanelTitle")
    add(" ")
  end
  add("Agent changes", "AgentdiffPanelTitle")
  local n, added, removed = #s.order, 0, 0
  for _, p in ipairs(s.order) do
    added, removed = added + s.files[p].added, removed + s.files[p].removed
  end
  if n == 0 then
    title.right = { { "nothing pending", "AgentdiffPanelCount" } }
  else
    title.right = { { ("%d file%s  "):format(n, n == 1 and "" or "s"), "AgentdiffPanelCount" } }
    vim.list_extend(title.right, counts(added, removed))
  end
  rows[1] = title
  rows[2] = (row("blank"))
  if view == "tree" then
    tree_rows(s, build_tree(s), 0, rows, with_icons)
  else
    list_rows(s, rows, with_icons)
  end
  rows[#rows + 1] = (row("blank"))
  if help then
    for _, k in ipairs(help_keys) do
      local r, a = row("help")
      a(" ")
      a(k[1], "AgentdiffPanelKey")
      a(" " .. k[2], "AgentdiffPanelHelp")
      rows[#rows + 1] = r
    end
  else
    local r, a = row("help")
    a(" ")
    a("?", "AgentdiffPanelKey")
    a(" keys", "AgentdiffPanelHelp")
    rows[#rows + 1] = r
  end
  return rows
end

---A row as plain text with its right-aligned part (tests, debugging).
---@param r AgentdiffPanelRow
---@return string
function M.row_text(r)
  local right = table.concat(vim.tbl_map(function(c)
    return c[1]
  end, r.right))
  return right ~= "" and (r.text .. " | " .. right) or r.text
end

-- Rendering -------------------------------------------------------------------

---@return AgentdiffPanelRow?
local function row_at_cursor()
  if not M.is_open() then
    return nil
  end
  return state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
end

---@param r AgentdiffPanelRow?
---@return string?
local function row_id(r)
  return r and (r.path and ("f:" .. r.path) or r.dir and ("d:" .. r.dir)) or nil
end

---Redraw the panel, keeping the cursor on the same file or folder.
function M.render()
  local s = session.get()
  if not s or not M.is_open() or not state.buf then
    return
  end
  local win = state.win --[[@as integer]]
  local buf = state.buf --[[@as integer]]
  local keep_id = row_id(row_at_cursor())
  local keep_row = vim.api.nvim_win_get_cursor(win)[1]
  local rows = M.rows(s, state.view or "tree", state.help)
  state.rows = rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(r)
      return r.text
    end, rows)
  )
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for i, r in ipairs(rows) do
    for _, m in ipairs(r.marks) do
      vim.api.nvim_buf_set_extmark(buf, M.ns, i - 1, m[1], { end_col = m[2], hl_group = m[3] })
    end
    if #r.right > 0 then
      local chunks = vim.deepcopy(r.right)
      table.insert(chunks, { " ", "Normal" })
      vim.api.nvim_buf_set_extmark(buf, M.ns, i - 1, 0, { virt_text = chunks, virt_text_pos = "right_align" })
    end
  end
  local target
  for i, r in ipairs(rows) do
    if keep_id and row_id(r) == keep_id then
      target = i
      break
    end
  end
  if not target then
    -- the nearest file or folder to where the cursor was, else the first one
    target = math.min(math.max(keep_row, 3), #rows)
    if not (rows[target] and (rows[target].path or rows[target].dir)) then
      for i, r in ipairs(rows) do
        if r.path or r.dir then
          target = i
          break
        end
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
end

-- Window ----------------------------------------------------------------------

---Columns (left/right) or rows (top/bottom) for the panel.
---@param o AgentdiffPanelOptions
---@return integer
function M.size(o)
  local vertical = o.position == "left" or o.position == "right"
  local total = vertical and vim.o.columns or (vim.o.lines - vim.o.cmdheight - 1)
  local size = o.size
  local share
  if type(size) == "string" then
    share = tonumber(size:match("^(%d+)%%$")) / 100
  elseif size < 1 then
    share = size
  end
  local n = share and math.floor(total * share) or math.floor(size --[[@as number]])
  return math.max(1, math.min(n, total - 1))
end

---@param o AgentdiffPanelOptions
local function apply_size(o)
  local win = M.win()
  if not win then
    return
  end
  if o.position == "left" or o.position == "right" then
    vim.api.nvim_win_set_width(win, M.size(o))
  else
    vim.api.nvim_win_set_height(win, M.size(o))
  end
end

local function on_activate()
  local r = row_at_cursor()
  if not r then
    return
  end
  if r.dir then
    collapsed[r.dir] = not collapsed[r.dir] or nil
    return M.render()
  end
  if r.path then
    windows.focus_editing()
    handlers.open(r.path)
  end
end

---@param fn fun(path: string)
local function on_file(fn)
  local r = row_at_cursor()
  if r and r.path then
    fn(r.path)
  end
end

---@param buf integer
local function map_keys(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "agentdiff: " .. desc })
  end
  map("<CR>", on_activate, "Open file / fold folder")
  map("o", on_activate, "Open file / fold folder")
  map("<2-LeftMouse>", on_activate, "Open file / fold folder")
  map("K", function()
    on_file(function(p)
      handlers.keep({ scope = "file", path = p })
    end)
  end, "Keep file")
  map("U", function()
    on_file(function(p)
      handlers.undo({ scope = "file", path = p })
    end)
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
  map("t", function()
    M.set_view(state.view == "tree" and "list" or "tree")
  end, "Tree / list")
  map("?", function()
    state.help = not state.help
    M.render()
  end, "Keys")
  map("q", M.close, "Close")
end

local function open_window()
  local o = popts()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "agentdiff"
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, "agentdiff://changes")
  local side = ({ right = "right", left = "left", top = "above", bottom = "below" })[o.position]
  ---@type vim.api.keyset.win_config
  local cfg = { split = side, win = -1 }
  if o.position == "left" or o.position == "right" then
    cfg.width = M.size(o)
  else
    cfg.height = M.size(o)
  end
  local win = vim.api.nvim_open_win(buf, true, cfg)
  for k, v in pairs({
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    cursorline = true,
    wrap = false,
    spell = false,
    list = false,
    winfixwidth = true,
    winfixheight = true,
    winfixbuf = true,
  }) do
    vim.wo[win][k] = v
  end
  state.buf, state.win = buf, win
  map_keys(buf)
  local g = vim.api.nvim_create_augroup("agentdiff_panel", { clear = true })
  state.group = g
  vim.api.nvim_create_autocmd("User", { group = g, pattern = "AgentdiffChanged", callback = M.render })
  vim.api.nvim_create_autocmd("VimResized", {
    group = g,
    callback = function()
      apply_size(popts())
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = g,
    pattern = tostring(win),
    callback = function()
      vim.schedule(M.close)
    end,
  })
end

---Show a view in the open panel.
---@param view AgentdiffPanelView
function M.set_view(view)
  state.view = view
  last_view = view
  M.render()
end

---Open the panel (or switch the open panel) in a view.
---@param view? AgentdiffPanelView  default: the last view used, else `panel.view`
function M.open(view)
  local s = session.get()
  if not s then
    return
  end
  view = view or last_view or popts().view
  review_state.refresh(s)
  local win = M.win()
  if win and not vim.tbl_contains(vim.api.nvim_tabpage_list_wins(0), win) then
    M.close() -- open in another tab: move it here
  end
  win = M.win()
  if not win then
    open_window()
  else
    vim.api.nvim_set_current_win(win)
  end
  M.set_view(view)
end

function M.close()
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
    state.group = nil
  end
  local win = M.win()
  if win then
    pcall(vim.api.nvim_win_close, win, true)
  end
  state.win, state.buf, state.rows, state.view = nil, nil, {}, nil
end

---Toggle the panel. With a view: closed → open in it; showing it → close;
---showing the other view → switch to it.
---@param view? AgentdiffPanelView
function M.toggle(view)
  if not M.is_open() then
    return M.open(view)
  end
  if view and view ~= state.view then
    return M.open(view)
  end
  M.close()
end

---Forget collapsed folders, the last view and the key help (tests).
function M.reset()
  M.close()
  collapsed = {}
  last_view = nil
  state.help = false
end

return M
