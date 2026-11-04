local H = require("helpers")

local function scene(before, after, opts)
  for rel, text in pairs(before) do
    H.write(rel, text)
  end
  local agentdiff = H.start(opts)
  for rel, text in pairs(after) do
    H.write(rel, text)
  end
  H.poll()
  return agentdiff
end

---Panel rows as "text | right" strings.
local function panel_rows()
  local panel = require("agentdiff.ui.panel")
  local win = assert(panel.win(), "panel open")
  local buf = vim.api.nvim_win_get_buf(win)
  local rows = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local marks = vim.api.nvim_buf_get_extmarks(buf, panel.ns, 0, -1, { details = true })
  for i, l in ipairs(lines) do
    local right = {}
    for _, m in ipairs(marks) do
      if m[2] == i - 1 and m[4].virt_text then
        for _, c in ipairs(m[4].virt_text) do
          right[#right + 1] = c[1]
        end
      end
    end
    local r = vim.trim(table.concat(right))
    rows[i] = r ~= "" and (l .. " | " .. r) or l
  end
  return rows
end

---Put the panel cursor on the first row containing `text`.
local function panel_goto(text)
  local panel = require("agentdiff.ui.panel")
  local win = assert(panel.win())
  local buf = vim.api.nvim_win_get_buf(win)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(text, 1, true) then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { i, 0 })
      return i
    end
  end
  error("no panel row with " .. text)
end

local plain = { panel = { icons = false } }

describe("panel", function()
  it("lists files with status and counts (Panel lists counts)", function()
    local agentdiff = scene(
      { ["a.lua"] = "1\n2\n4\n" },
      { ["a.lua"] = "1\nX\nY\nZ\n4\n", ["b.lua"] = H.numbered(20) },
      plain
    )
    agentdiff.panel()
    local rows = panel_rows()
    ok(vim.tbl_contains(rows, "   a.lua | +3 −1  M"), vim.inspect(rows))
    ok(vim.tbl_contains(rows, "   b.lua | +20  A"), vim.inspect(rows))
    eq(" Agent changes | 2 files  +23 −1", rows[1])
  end)

  it("opens a file at its first change (Open from the panel)", function()
    local agentdiff = scene(
      { ["a.lua"] = H.numbered(10) },
      { ["a.lua"] = (H.numbered(10):gsub("l7\n", "A7\n")) }
    )
    agentdiff.panel()
    local panel_win = vim.api.nvim_get_current_win()
    panel_goto("a.lua")
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    ok(vim.api.nvim_get_current_win() ~= panel_win, "left the panel")
    eq("a.lua", vim.fn.expand("%:t"))
    eq(7, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("keeps and undoes files from the panel", function()
    local agentdiff = scene(
      { ["a.lua"] = "a\n", ["b.lua"] = "b\n" },
      { ["a.lua"] = "A\n", ["b.lua"] = "B\n" }
    )
    agentdiff.panel()
    panel_goto("a.lua")
    vim.api.nvim_feedkeys("K", "x", false)
    panel_goto("b.lua")
    vim.api.nvim_feedkeys("U", "x", false)
    H.poll()
    eq({}, H.pending())
    eq("A\n", H.read("a.lua"))
    eq("b\n", H.read("b.lua"))
  end)

  it("updates when pending changes change", function()
    local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" }, plain)
    agentdiff.panel()
    H.write("c.lua", "new\n")
    H.poll()
    ok(vim.tbl_contains(panel_rows(), "   c.lua | +1  A"), vim.inspect(panel_rows()))
  end)

  it("shows a tree with compacted, collapsible folders (Tree view)", function()
    local agentdiff = scene({ ["README.md"] = "r\n", ["lua/agentdiff/a.lua"] = "a\n" }, {
      ["README.md"] = "r\nR\n",
      ["lua/agentdiff/a.lua"] = "A\n",
      ["lua/agentdiff/ui/b.lua"] = "b\nb\n",
    }, plain)
    agentdiff.panel({ view = "tree" })
    eq({
      " Agent changes | 3 files  +4 −1",
      "",
      " ▾ lua/agentdiff | +3 −1",
      "   ▾ ui | +2",
      "       b.lua | +2  A",
      "     a.lua | +1 −1  M",
      "   README.md | +1  M",
      "",
      " ? keys",
    }, panel_rows())
    panel_goto("ui")
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    eq("   ▸ ui | +2", panel_rows()[4])
    eq("     a.lua | +1 −1  M", panel_rows()[5], "folded")
    eq("ui", vim.trim(vim.api.nvim_get_current_line()):sub(-2), "cursor stays on the folder")
    vim.api.nvim_feedkeys("o", "x", false)
    eq("       b.lua | +2  A", panel_rows()[5], "unfolded")
    -- keep from the tree
    panel_goto("a.lua")
    vim.api.nvim_feedkeys("K", "x", false)
    H.poll()
    eq(2, #H.pending())
  end)

  it("shows a list with each file's folder (List view)", function()
    local agentdiff = scene({ ["lua/a.lua"] = "a\n" }, { ["lua/a.lua"] = "A\n", ["top.lua"] = "t\n" }, plain)
    agentdiff.panel({ view = "list" })
    local rows = panel_rows()
    ok(vim.tbl_contains(rows, " a.lua  lua | +1 −1  M"), vim.inspect(rows))
    ok(vim.tbl_contains(rows, " top.lua | +1  A"), vim.inspect(rows))
    panel_goto("top.lua")
    vim.api.nvim_feedkeys("U", "x", false)
    H.poll()
    eq({ "modified lua/a.lua +1 -1 #1" }, H.pending())
  end)

  it("colours rows and shows icons (Colours and icons)", function()
    local agentdiff = scene({ ["src/a.lua"] = "a\n" }, { ["src/a.lua"] = "A\n" })
    agentdiff.panel()
    local panel = require("agentdiff.ui.panel")
    local buf = vim.api.nvim_win_get_buf(panel.win())
    local groups = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, panel.ns, 0, -1, { details = true })) do
      if m[4].hl_group then
        groups[m[4].hl_group] = true
      end
      for _, c in ipairs(m[4].virt_text or {}) do
        groups[c[2]] = true
      end
    end
    for _, g in ipairs({
      "AgentdiffPanelTitle",
      "AgentdiffPanelDir",
      "AgentdiffPanelAdded",
      "AgentdiffPanelRemoved",
      "AgentdiffPanelModified",
      "AgentdiffPanelFileIcon",
      "AgentdiffPanelDirIcon",
    }) do
      ok(groups[g], g .. " used: " .. vim.inspect(vim.tbl_keys(groups)))
    end
    local icons = require("agentdiff.ui.icons")
    local text = table.concat(panel_rows(), "\n")
    ok(text:find(icons.glyphs.file, 1, true) and text:find(icons.glyphs.dir_open, 1, true), text)
  end)

  it("uses mini.icons when it is set up", function()
    _G.MiniIcons = {
      get = function(kind, name)
        return kind == "file" and ("X" .. name:sub(-3)) or nil, "MiniIconsBlue"
      end,
    }
    local ok_, err = pcall(function()
      local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" })
      agentdiff.panel()
      ok(table.concat(panel_rows(), "\n"):find("Xlua a.lua", 1, true), vim.inspect(panel_rows()))
    end)
    _G.MiniIcons = nil
    assert(ok_, err)
  end)

  it("shows every key with ?", function()
    local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" }, plain)
    agentdiff.panel()
    vim.api.nvim_feedkeys("?", "x", false)
    local text = table.concat(panel_rows(), "\n")
    ok(text:find("gK/gU keep/undo all", 1, true) and text:find("t tree/list", 1, true), text)
  end)
end)

describe("panel views", function()
  local panel = function()
    return require("agentdiff.ui.panel")
  end

  it("toggles a view and switches between views (Toggle a view / Switch views)", function()
    local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" })
    agentdiff.panel({ view = "tree" })
    eq("tree", panel().view())
    agentdiff.panel({ view = "list" })
    eq("list", panel().view(), "switched, still open")
    agentdiff.panel({ view = "list" })
    eq(nil, panel().view(), "closed")
    agentdiff.panel()
    eq("list", panel().view(), "reopens in the last view")
    vim.api.nvim_feedkeys("t", "x", false)
    eq("tree", panel().view(), "t switches")
    agentdiff.panel()
    eq(nil, panel().view())
  end)

  it("opens in the configured view and rejects unknown ones", function()
    local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" }, { panel = { view = "list" } })
    agentdiff.panel()
    eq("list", panel().view())
    agentdiff.panel({ view = "grid" })
    eq("list", panel().view(), "unchanged")
  end)

  it("maps panel_tree and panel_list, and :Agentdiff panel tree|list", function()
    scene(
      { ["a.lua"] = "a\n" },
      { ["a.lua"] = "A\n" },
      { keymaps = { panel_tree = "<F7>", panel_list = "<F8>" } }
    )
    vim.api.nvim_feedkeys(vim.keycode("<F7>"), "x", false)
    eq("tree", panel().view())
    vim.api.nvim_feedkeys(vim.keycode("<F8>"), "x", false)
    eq("list", panel().view())
    vim.api.nvim_feedkeys(vim.keycode("<F8>"), "x", false)
    eq(nil, panel().view())
    vim.cmd("Agentdiff panel tree")
    eq("tree", panel().view())
    vim.cmd("Agentdiff panel")
    eq(nil, panel().view())
    local command = require("agentdiff.command")
    eq(
      { "list", "tree" },
      vim.fn.sort(command.complete(require("agentdiff").subcommands, "", "Agentdiff panel "))
    )
  end)
end)

describe("panel position and size", function()
  local function panel_win(opts)
    local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" }, { panel = opts })
    H.edit("a.lua")
    agentdiff.panel()
    return require("agentdiff.ui.panel").win()
  end

  it("opens at the right edge, 40 columns wide, by default", function()
    local win = panel_win(nil)
    eq(40, vim.api.nvim_win_get_width(win))
    eq(vim.o.columns - 40, vim.api.nvim_win_get_position(win)[2])
  end)

  it("opens at the left edge with a share of the width (Position and size)", function()
    local win = panel_win({ position = "left", size = "25%" })
    eq(0, vim.api.nvim_win_get_position(win)[2])
    eq(math.floor(vim.o.columns * 0.25), vim.api.nvim_win_get_width(win))
  end)

  it("opens at the top or bottom with a fixed or fractional height", function()
    local win = panel_win({ position = "top", size = 8 })
    eq(8, vim.api.nvim_win_get_height(win))
    eq(vim.o.columns, vim.api.nvim_win_get_width(win))
    eq(0, vim.api.nvim_win_get_position(win)[1])
    require("agentdiff")._test.reset()
    local w2 = panel_win({ position = "bottom", size = 0.5 })
    eq(math.floor((vim.o.lines - vim.o.cmdheight - 1) * 0.5), vim.api.nvim_win_get_height(w2))
    ok(vim.api.nvim_win_get_position(w2)[1] > 0, "at the bottom")
  end)

  it("keeps a share of the editor when it is resized", function()
    local win = panel_win({ size = "50%" })
    local cols = vim.o.columns
    vim.o.columns = cols - 20
    vim.api.nvim_exec_autocmds("VimResized", {})
    eq(math.floor((cols - 20) * 0.5), vim.api.nvim_win_get_width(win))
    vim.o.columns = cols
  end)

  it("computes the size with a function (Size from a function)", function()
    local cols = vim.o.columns
    vim.o.columns = 100
    local seen
    local win = panel_win({
      size = function(ctx)
        seen = ctx
        return math.max(45, math.floor(ctx.total * 0.3))
      end,
    })
    eq({ position = "right", total = 100 }, seen)
    eq(45, vim.api.nvim_win_get_width(win))
    vim.o.columns = 200
    vim.api.nvim_exec_autocmds("VimResized", {})
    eq(60, vim.api.nvim_win_get_width(win))
    vim.o.columns = cols
  end)

  it("falls back to 40 columns when the size function fails", function()
    local win = panel_win({
      size = function()
        return "wide"
      end,
    })
    eq(40, vim.api.nvim_win_get_width(win))
    require("agentdiff")._test.reset()
    win = panel_win({
      size = function()
        error("boom")
      end,
    })
    eq(40, vim.api.nvim_win_get_width(win))
  end)

  it("rejects invalid options", function()
    for _, p in ipairs({
      { view = "grid" },
      { position = "middle" },
      { size = "half" },
      { size = -3 },
      { size = "0%" },
    }) do
      ok(not pcall(require("agentdiff").setup, { auto_start = false, panel = p }), vim.inspect(p))
    end
  end)
end)

describe("side-by-side", function()
  it("shows a read-only baseline next to the file in diff mode and toggles back (Toggle the view)", function()
    local agentdiff = scene({ ["s.lua"] = "a\nold\nc\n" }, { ["s.lua"] = "a\nnew\nc\n" })
    local buf = H.edit("s.lua")
    local file_win = vim.api.nvim_get_current_win()
    agentdiff.toggle_view()
    local wins = vim.api.nvim_tabpage_list_wins(0)
    eq(2, #wins)
    local base_win = wins[1] == file_win and wins[2] or wins[1]
    local base_buf = vim.api.nvim_win_get_buf(base_win)
    eq({ "a", "old", "c" }, vim.api.nvim_buf_get_lines(base_buf, 0, -1, false))
    eq(false, vim.bo[base_buf].modifiable)
    ok(vim.wo[base_win].diff and vim.wo[file_win].diff, "both windows in diff mode")
    eq(
      0,
      #vim.api.nvim_buf_get_extmarks(buf, require("agentdiff.ui.overlay").ns, 0, -1, {}),
      "overlay hidden"
    )
    -- keep works in this view, from the file window
    vim.api.nvim_win_set_cursor(file_win, { 2, 0 })
    agentdiff.keep()
    eq({}, H.pending())
    eq({ "a", "new", "c" }, vim.api.nvim_buf_get_lines(base_buf, 0, -1, false), "baseline window follows")
    agentdiff.toggle_view()
    eq(1, #vim.api.nvim_tabpage_list_wins(0))
    ok(not vim.wo[file_win].diff)
  end)

  it("undoes from the baseline window", function()
    local agentdiff = scene({ ["u.lua"] = "a\nold\nc\n" }, { ["u.lua"] = "a\nnew\nc\n" })
    H.edit("u.lua")
    agentdiff.toggle_view()
    local base_win = vim.fn.win_getid(1)
    vim.api.nvim_set_current_win(base_win)
    ok(vim.b.agentdiff_baseline_of ~= nil, "in the baseline window")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    agentdiff.undo()
    eq("a\nold\nc\n", H.read("u.lua"))
  end)
end)

describe("binary and oversized files", function()
  it("lists binary files without an overlay, kept or undone whole (Binary file changed)", function()
    local agentdiff = scene({ ["logo.png"] = "\137PNG\0\1\2" }, { ["logo.png"] = "\137PNG\0\9\9\9" })
    eq({ "binary logo.png +0 -0 #0" }, H.pending())
    local buf = H.edit("logo.png")
    eq(0, #vim.api.nvim_buf_get_extmarks(buf, require("agentdiff.ui.overlay").ns, 0, -1, {}))
    agentdiff.undo({ scope = "hunk" })
    eq("\137PNG\0\1\2", H.read("logo.png"), "undone as a whole file")
    H.poll()
    eq({}, H.pending())
  end)

  it("treats files above the size limit as whole files", function()
    local agentdiff = scene(
      { ["big.txt"] = ("x"):rep(200) .. "\n" },
      { ["big.txt"] = ("y"):rep(200) .. "\n" },
      {
        max_file_size = 100,
      }
    )
    eq({ "binary big.txt +0 -0 #0" }, H.pending())
    agentdiff.keep({ path = "big.txt" })
    eq({}, H.pending())
  end)
end)

describe("command, event and status", function()
  it("completes subcommand names (Subcommand completion)", function()
    H.start()
    local got = vim.fn.getcompletion("Agentdiff ", "cmdline")
    for _, n in ipairs({ "keep", "undo", "next", "prev", "panel", "view", "overlay", "resolve" }) do
      ok(vim.tbl_contains(got, n), n .. " in " .. vim.inspect(got))
    end
    eq({ "keep", "keep_all", "keep_file" }, vim.fn.getcompletion("Agentdiff ke", "cmdline"))
  end)

  it("runs actions through :Agentdiff, with a range", function()
    H.write("c.lua", H.numbered(9))
    H.start()
    H.write("c.lua", (H.numbered(9):gsub("l9\n", "l9\nn10\nn11\n")))
    H.poll()
    H.edit("c.lua")
    vim.cmd("10,10Agentdiff keep")
    eq({ "modified c.lua +1 -0 #1" }, H.pending())
    vim.cmd("Agentdiff keep_file")
    eq({}, H.pending())
  end)

  it("fires User AgentdiffChanged when pending changes change (Change event)", function()
    H.write("e.lua", "a\n")
    local agentdiff = H.start()
    local fired = 0
    vim.api.nvim_create_autocmd("User", {
      pattern = "AgentdiffChanged",
      callback = function()
        fired = fired + 1
      end,
    })
    H.write("e.lua", "b\n")
    H.poll()
    eq(1, fired, "on detection")
    H.edit("e.lua")
    agentdiff.keep()
    eq(2, fired, "on keep")
    H.poll()
    eq(2, fired, "not when nothing changed")
  end)

  it("summarises pending changes (Summary with pending changes / Nothing pending)", function()
    local agentdiff = scene({ ["a.lua"] = H.numbered(30), ["b.lua"] = "b\n", ["c.lua"] = "c\n" }, {
      ["a.lua"] = H.numbered(30)
        :gsub("l2\n", "X\n")
        :gsub("l10\n", "X\n")
        :gsub("l20\n", "X\n")
        :gsub("l29\n", "X\n"),
      ["b.lua"] = "B\n",
      ["c.lua"] = "C\nC2\n",
    })
    eq(7, #H.pending() + 4, "sanity")
    eq("3 files · 6 changes", agentdiff.status())
    agentdiff.keep_all({ force = true })
    eq("", agentdiff.status())
  end)
end)

describe("path status", function()
  it("marks a changed file and every parent directory (File and its parents)", function()
    H.write("src/app/main.lua", "a\n")
    H.write("src/other.lua", "o\n")
    local agentdiff = H.start()
    H.write("src/app/main.lua", "agent\n")
    H.write("gone/old.lua", "x\n")
    H.poll()
    eq("file", agentdiff.path_status(H.path("src/app/main.lua")))
    eq("file", agentdiff.path_status("src/app/main.lua"))
    eq("dir", agentdiff.path_status(H.path("src/app")))
    eq("dir", agentdiff.path_status(H.path("src") .. "/"))
    eq("dir", agentdiff.path_status(H.project))
    eq(nil, agentdiff.path_status(H.path("src/other.lua")))
    eq(nil, agentdiff.path_status("/somewhere/else.lua"))
    -- created files count; deleted files mark their directory
    eq("file", agentdiff.path_status("gone/old.lua"))
    H.remove("gone/old.lua")
    H.poll()
    eq(nil, agentdiff.path_status("gone/old.lua"), "created then deleted: nothing pending")
  end)

  it("returns nil everywhere once everything is reviewed (Nothing pending)", function()
    H.write("src/main.lua", "a\n")
    H.write("src/gone.lua", "g\n")
    local agentdiff = H.start()
    H.write("src/main.lua", "agent\n")
    H.remove("src/gone.lua")
    H.poll()
    eq("file", agentdiff.path_status("src/gone.lua"), "a deleted file is pending")
    eq("dir", agentdiff.path_status("src"))
    agentdiff.keep_all({ force = true })
    eq(nil, agentdiff.path_status("src/main.lua"))
    eq(nil, agentdiff.path_status("src"))
    eq(nil, agentdiff.path_status(H.project))
  end)

  it("defines the tree highlight groups", function()
    require("agentdiff.ui.highlights").define()
    eq("DiagnosticWarn", vim.api.nvim_get_hl(0, { name = "AgentdiffTreeFile" }).link)
    eq("DiagnosticWarn", vim.api.nvim_get_hl(0, { name = "AgentdiffTreeDir" }).link)
  end)
end)

describe("panel window", function()
  local function panel_with(agentdiff)
    agentdiff.panel()
    local win = vim.api.nvim_get_current_win()
    panel_goto("a.lua")
    return win, vim.api.nvim_win_get_buf(win)
  end

  it("opens files in an editing window, never the panel (Files never open in the panel)", function()
    local agentdiff = scene(
      { ["a.lua"] = "a\n", ["b.lua"] = "b\n" },
      { ["a.lua"] = "A\n", ["b.lua"] = "B\n" }
    )
    H.edit("b.lua")
    local file_win = vim.api.nvim_get_current_win()
    local pwin, pbuf = panel_with(agentdiff)
    vim.api.nvim_feedkeys("o", "x", false)
    eq(file_win, vim.api.nvim_get_current_win())
    eq("a.lua", vim.fn.expand("%:t"))
    eq(pbuf, vim.api.nvim_win_get_buf(pwin), "the panel still shows the panel")
    -- navigation from inside the panel
    vim.api.nvim_set_current_win(pwin)
    agentdiff.next()
    ok(vim.api.nvim_get_current_win() ~= pwin, "left the panel")
    eq(pbuf, vim.api.nvim_win_get_buf(pwin))
    -- :edit in the panel fails
    vim.api.nvim_set_current_win(pwin)
    ok(not pcall(vim.cmd.edit, H.path("b.lua")), ":edit refused in the panel")
    eq(pbuf, vim.api.nvim_win_get_buf(pwin))
  end)

  it("opens a split when the panel is the only window left", function()
    local agentdiff = scene({ ["a.lua"] = "a\n" }, { ["a.lua"] = "A\n" })
    local pwin, pbuf = panel_with(agentdiff)
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= pwin then
        vim.api.nvim_win_close(w, true)
      end
    end
    eq(1, #vim.api.nvim_tabpage_list_wins(0))
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    eq(2, #vim.api.nvim_tabpage_list_wins(0))
    ok(vim.api.nvim_get_current_win() ~= pwin, "a new window")
    eq("a.lua", vim.fn.expand("%:t"))
    eq(pbuf, vim.api.nvim_win_get_buf(pwin))
  end)

  it("skips special windows like a side-by-side baseline", function()
    local agentdiff = scene({ ["a.lua"] = "a\nb\n" }, { ["a.lua"] = "a\nB\n" })
    H.edit("a.lua")
    local file_win = vim.api.nvim_get_current_win()
    agentdiff.toggle_view() -- opens a nofile baseline window
    local base_win
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= file_win then
        base_win = w
      end
    end
    vim.api.nvim_set_current_win(base_win)
    local pwin = panel_with(agentdiff)
    vim.api.nvim_feedkeys("o", "x", false)
    eq(file_win, vim.api.nvim_get_current_win())
    ok(pwin ~= file_win)
  end)
end)
