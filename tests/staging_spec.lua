local H = require("helpers")

---Stage exact content for a path (what a hunk-level `git add -p` produces).
local function stage_content(rel, text)
  local tmp = H.state .. "/stage.tmp"
  H.write_abs(tmp, text)
  local sha = vim.trim(H.git({ "hash-object", "-w", tmp }))
  H.git({ "update-index", "--cacheinfo", "100644," .. sha .. "," .. rel })
end

describe("staging keeps changes", function()
  local base = H.numbered(30)
  local both = base:gsub("l5\n", "agent5\n"):gsub("l25\n", "agent25\n")

  before_each(function()
    H.write("t.lua", base)
    H.write("other.lua", "o\n")
    H.git_repo()
  end)

  it("keeps a file staged in git (Stage a file)", function()
    H.start()
    H.write("t.lua", both)
    H.poll()
    eq({ "modified t.lua +2 -2 #2" }, H.pending())
    H.git({ "add", "t.lua" })
    H.poll()
    eq({}, H.pending())
    eq(both, H.read("t.lua"), "the file is unchanged on disk")
  end)

  it("keeps only the staged hunk (Stage one hunk)", function()
    H.start()
    H.write("t.lua", both)
    H.poll()
    stage_content("t.lua", (base:gsub("l5\n", "agent5\n")))
    H.poll()
    eq({ "modified t.lua +1 -1 #1" }, H.pending())
    eq(24, require("agentdiff").files()[1].hunks[1].b_lo, "the unstaged region is still pending")
  end)

  it("keeps what `git commit -a` commits (Commit all)", function()
    H.start()
    H.write("t.lua", both)
    H.poll()
    H.git({ "commit", "-q", "-am", "agent work" })
    H.poll()
    eq({}, H.pending())
  end)

  it("keeps a created file once it is staged", function()
    H.start()
    H.write("new.lua", "fresh\n")
    H.poll()
    eq({ "created new.lua +1 -0 #1" }, H.pending())
    H.git({ "add", "new.lua" })
    H.poll()
    eq({}, H.pending())
  end)

  it("keeps a staged deletion", function()
    H.start()
    H.remove("other.lua")
    H.poll()
    eq({ "deleted other.lua +0 -1 #1" }, H.pending())
    H.git({ "rm", "-q", "--cached", "other.lua" })
    H.poll()
    eq({}, H.pending())
  end)

  it("never makes anything pending by unstaging (Unstage after staging)", function()
    H.start()
    H.write("t.lua", both)
    H.poll()
    H.git({ "add", "t.lua" })
    H.poll()
    eq({}, H.pending())
    H.git({ "restore", "--staged", "t.lua" })
    H.poll()
    eq({}, H.pending(), "unstaging a kept change")
    -- the user's own saved work, staged then unstaged
    H.edit("other.lua")
    H.change(1, 1, { "mine" })
    H.save()
    H.git({ "add", "other.lua" })
    H.poll()
    H.git({ "restore", "--staged", "other.lua" })
    H.poll()
    eq({}, H.pending(), "unstaging your own work")
  end)

  it("leaves staged agent edits pending when turned off (Staging keeps disabled)", function()
    H.start({ keep_on_stage = false })
    H.write("t.lua", both)
    H.poll()
    H.git({ "add", "t.lua" })
    H.poll()
    eq({ "modified t.lua +2 -2 #2" }, H.pending())
  end)

  it("keeps an agent edit the agent staged in the same instant", function()
    H.start()
    H.write("t.lua", both)
    H.git({ "add", "t.lua" })
    H.poll()
    eq({}, H.pending())
  end)
end)

describe("keep and undo end a conflict", function()
  local base = H.numbered(10)

  ---A conflicted f.lua: unsaved edits on lines 3 and 8, the agent rewrote line 3.
  local function conflict()
    H.write("f.lua", base)
    local agentdiff = H.start()
    local buf = H.edit("f.lua")
    H.change(3, 3, { "mine3" })
    H.change(8, 8, { "mine8" })
    H.write("f.lua", (base:gsub("l3\n", "agent3\n")))
    vim.cmd("silent! checktime")
    vim.wait(50)
    H.poll()
    agentdiff._test.flush()
    eq({ "conflicted f.lua +1 -1 #1" }, H.pending())
    return agentdiff, buf
  end

  ---Count FileChangedShell events a :checktime triggers (a stale buffer would).
  local function stale(buf)
    local n = 0
    local id = vim.api.nvim_create_autocmd("FileChangedShell", {
      callback = function()
        n = n + 1
        vim.v.fcs_choice = ""
      end,
    })
    vim.cmd("silent! checktime " .. buf)
    vim.api.nvim_del_autocmd(id)
    return n
  end

  it("keeps the agent's version with your other unsaved edits (Keep a conflicted file)", function()
    local agentdiff, buf = conflict()
    agentdiff.keep_file()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq("agent3", lines[3], "the agent wins where it overlapped")
    eq("mine8", lines[8], "your other unsaved edit stays")
    ok(vim.bo[buf].modified)
    eq({}, H.pending())
    eq(nil, agentdiff.path_status("f.lua"), "no file-tree mark")
    eq(0, stale(buf), "the buffer matches the disk")
    H.save()
    H.poll()
    eq({}, H.pending())
    eq((base:gsub("l3\n", "agent3\n"):gsub("l8\n", "mine8\n")), H.read("f.lua"))
  end)

  it("undoes the agent's changes and keeps yours (Undo a conflicted file)", function()
    local agentdiff, buf = conflict()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    agentdiff.undo()
    eq(base, H.read("f.lua"), "disk back to the baseline")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq({ "mine3", "mine8" }, { lines[3], lines[8] }, "your unsaved edits stay")
    eq({}, H.pending())
    eq(nil, agentdiff.path_status("f.lua"))
    eq(0, stale(buf))
  end)
end)

describe("stale pending changes", function()
  local function restart()
    local agentdiff = require("agentdiff")
    agentdiff.stop()
    agentdiff.start()
    assert(agentdiff._test.wait_ready(5000))
    return agentdiff
  end

  before_each(function()
    H.write("t.lua", "a\nb\n")
    H.write("gone.lua", "g\n")
    H.git_repo()
  end)

  it("keeps changes committed while review wasn't running (Committed before review started)", function()
    local agentdiff = H.start()
    H.write("t.lua", "a\nagent\n")
    H.poll()
    eq({ "modified t.lua +1 -1 #1" }, H.pending())
    agentdiff.stop()
    H.git({ "commit", "-q", "-am", "committed while Neovim was closed" })
    restart()
    eq({}, H.pending())
  end)

  it("keeps a committed deletion of a tracked file (Committed deletion)", function()
    local agentdiff = H.start()
    H.remove("gone.lua")
    H.poll()
    eq({ "deleted gone.lua +0 -1 #1" }, H.pending())
    agentdiff.stop()
    H.git({ "rm", "-q", "--cached", "gone.lua" })
    H.git({ "commit", "-q", "-m", "delete gone.lua" })
    restart()
    eq({}, H.pending())
  end)

  it("keeps a deletion committed while running", function()
    H.start()
    H.remove("gone.lua")
    H.poll()
    H.git({ "rm", "-q", "--cached", "gone.lua" })
    H.git({ "commit", "-q", "-m", "delete gone.lua" })
    H.poll()
    eq({}, H.pending())
  end)

  it("leaves the deletion of a never-tracked file pending", function()
    H.write("scratch.txt", "untracked\n")
    local agentdiff = H.start()
    H.remove("scratch.txt")
    H.poll()
    eq({ "deleted scratch.txt +0 -1 #1" }, H.pending())
    H.git({ "commit", "-q", "--allow-empty", "-m", "unrelated" })
    agentdiff = restart()
    eq({ "deleted scratch.txt +0 -1 #1" }, H.pending())
    local _ = agentdiff
  end)

  it("leaves uncommitted, unstaged agent changes pending at startup", function()
    H.start()
    H.write("t.lua", "a\nagent\n")
    H.poll()
    restart()
    eq({ "modified t.lua +1 -1 #1" }, H.pending())
  end)
end)

describe("reset", function()
  it("forgets the current project's pending changes (Reset the current project)", function()
    H.write("r.lua", "base\n")
    local agentdiff = H.start()
    H.write("r.lua", "agent\n")
    H.poll()
    eq({ "modified r.lua +1 -1 #1" }, H.pending())
    agentdiff.reset({ force = true })
    ok(agentdiff._test.wait_ready(5000), "review continues")
    eq({}, H.pending())
    H.write("r.lua", "agent again\n")
    H.poll()
    eq({ "modified r.lua +1 -1 #1" }, H.pending(), "later agent changes show as usual")
  end)

  it("asks first", function()
    H.write("r.lua", "base\n")
    local agentdiff = H.start()
    H.write("r.lua", "agent\n")
    H.poll()
    local orig = vim.fn.confirm
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.confirm = function()
      return 2
    end
    vim.cmd("Agentdiff reset")
    vim.fn.confirm = orig
    eq({ "modified r.lua +1 -1 #1" }, H.pending(), "declining keeps everything")
  end)

  it("leaves other projects alone (Other projects untouched)", function()
    local other = H.state .. "/other-project"
    vim.fn.mkdir(other, "p")
    H.write_abs(other .. "/o.lua", "o\n")
    H.write("a.lua", "a\n")
    local agentdiff = H.start()
    H.write("a.lua", "agent a\n")
    H.poll()
    eq({ "modified a.lua +1 -1 #1" }, H.pending())
    -- switch to the other project, give it a pending change, reset it
    agentdiff.setup({
      root = other,
      state_dir = H.state .. "/agentdiff",
      poll_interval = 0,
      auto_start = false,
    })
    agentdiff.start()
    assert(agentdiff._test.wait_ready(5000))
    H.write_abs(other .. "/o.lua", "agent o\n")
    H.poll()
    eq({ "modified o.lua +1 -1 #1" }, H.pending())
    agentdiff.reset({ force = true })
    assert(agentdiff._test.wait_ready(5000))
    eq({}, H.pending())
    -- back to the first project: its pending change is still there
    agentdiff.setup({
      root = H.project,
      state_dir = H.state .. "/agentdiff",
      poll_interval = 0,
      auto_start = false,
    })
    agentdiff.start()
    assert(agentdiff._test.wait_ready(5000))
    eq({ "modified a.lua +1 -1 #1" }, H.pending())
  end)
end)
