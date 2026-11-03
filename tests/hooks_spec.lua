local H = require("helpers")

local journal = require("agentdiff.core.journal")

local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local reporter = repo .. "/bin/agentdiff-hook.lua"

---Run the reporter as the agent CLI would.
---@param input string|table  payload (a table is JSON-encoded)
---@param harness? string
---@param hint? string
---@return vim.SystemCompleted
local function report(input, harness, hint)
  local cmd = { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", reporter }
  vim.list_extend(cmd, { harness or "claude", H.state .. "/agentdiff", hint })
  local stdin = type(input) == "table" and vim.json.encode(input) or input
  return vim.system(cmd, { stdin = stdin, text = true }):wait()
end

---A Claude Code payload for an edit of a project file.
---@param rel string
---@param event? string
---@param tool? string
local function claude_edit(rel, event, tool)
  return {
    session_id = "s1",
    cwd = H.project,
    hook_event_name = event or "PostToolUse",
    tool_name = tool or "Edit",
    tool_input = { file_path = H.path(rel) },
  }
end

local function store_dir()
  return require("agentdiff")._test.session().store.dir
end

---@param rel string
---@param ms integer  wall-clock ms
local function set_mtime(rel, ms)
  vim.uv.fs_utime(H.path(rel), ms / 1000, ms / 1000)
end

describe("hook reporter", function()
  it("records an edit in the project's store (Edit payload)", function()
    H.start()
    local r = report(claude_edit("src/a.lua", "PreToolUse"))
    eq(0, r.code)
    eq("", r.stdout)
    eq("", r.stderr)
    local t = journal.times(store_dir())
    eq(1, #t["src/a.lua"])
    local last = journal.last(store_dir())
    ok(last.claude, "last report remembered")
  end)

  it("records nothing for other tools or bad input (Not a file edit)", function()
    H.start()
    for _, input in ipairs({
      { tool_name = "Bash", cwd = H.project, tool_input = { command = "sed -i s/a/b/ " .. H.path("a.lua") } },
      { tool_name = "Read", cwd = H.project, tool_input = { file_path = H.path("a.lua") } },
      "not json",
      "",
      "[1, 2]",
    }) do
      local r = report(input)
      eq(0, r.code)
      eq("", r.stdout .. r.stderr)
    end
    local r = report(claude_edit("a.lua"), "nonsense")
    eq(0, r.code, "an unknown harness name falls back to every adapter")
    eq({ "a.lua" }, vim.tbl_keys(journal.times(store_dir())))
  end)

  it("records nothing for files outside reviewed projects", function()
    H.start()
    local outside = vim.fn.tempname() .. "-elsewhere"
    vim.fn.mkdir(outside, "p")
    local r = report({ tool_name = "Write", cwd = outside, tool_input = { file_path = outside .. "/x.lua" } })
    eq(0, r.code)
    eq({}, journal.times(store_dir()))
    eq(nil, vim.uv.fs_stat(H.state .. "/agentdiff/agent"))
    vim.fn.delete(outside, "rf")
  end)

  it("exits 0 without a state directory", function()
    local r = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", reporter }, { stdin = "{}" })
      :wait()
    eq(0, r.code)
  end)
end)

describe("hooks attribution", function()
  local function start()
    return H.start({ attribution = "hooks" })
  end

  it("reviews an edit an agent hook reported (Reported agent edit)", function()
    H.write("src/a.lua", "one\n")
    start()
    report(claude_edit("src/a.lua", "PreToolUse"))
    H.write("src/a.lua", "one\ntwo\n")
    report(claude_edit("src/a.lua", "PostToolUse"))
    H.poll()
    eq({ "modified src/a.lua +1 -0 #1" }, H.pending())
    eq({}, journal.times(store_dir()), "the reports were consumed")
  end)

  it("folds unreported changes into the baseline (Generated file)", function()
    H.write("src/gen.lua", "v1\n")
    start()
    H.write("src/gen.lua", "v2\n")
    H.write("src/new.lua", "created by a tool\n")
    H.poll()
    eq({}, H.pending())
    -- a later reported edit shows only its own change
    report(claude_edit("src/gen.lua"))
    H.write("src/gen.lua", "v2\nv3\n")
    H.poll()
    eq({ "modified src/gen.lua +1 -0 #1" }, H.pending())
  end)

  it("ignores edits the agent makes through its shell (Agent shell edit)", function()
    H.write("s.lua", "a\n")
    start()
    report(
      { tool_name = "Bash", cwd = H.project, tool_input = { command = "sed -i s/a/b/ s.lua" } },
      "claude",
      "pre"
    )
    H.write("s.lua", "b\n")
    H.poll()
    eq({}, H.pending())
  end)

  it("lets a report cover one change only (A report covers one change)", function()
    H.write("c.lua", "1\n")
    start()
    report(claude_edit("c.lua", "PreToolUse"))
    H.write("c.lua", "1\nagent\n")
    H.poll()
    eq({ "modified c.lua +1 -0 #1" }, H.pending())
    report(claude_edit("c.lua", "PostToolUse")) -- late post of the same edit
    H.write("c.lua", "script\n1\nagent\n")
    H.poll()
    eq({ "modified c.lua +1 -0 #1" }, H.pending(), "the script's line is not the agent's")
  end)

  it("reviews edits made while Neovim was closed (Neovim closed)", function()
    H.write("o.lua", "x\n")
    local agentdiff = start()
    local dir = store_dir()
    agentdiff.stop()
    -- an hour ago, with Neovim closed: the edit and its report
    local an_hour_ago = require("agentdiff.core.util").now_ms() - 3600 * 1000
    H.write("o.lua", "x\ny\n")
    set_mtime("o.lua", an_hour_ago + 50)
    journal.add(dir, { time = an_hour_ago, harness = "claude", phase = "pre", paths = { "o.lua" } })
    -- and a stale report whose tool call changed nothing, then a script edit now
    H.write("p.lua", "p\n")
    agentdiff.start()
    assert(agentdiff._test.wait_ready(5000))
    journal.add(dir, { time = an_hour_ago, harness = "claude", phase = "pre", paths = { "p.lua" } })
    H.write("p.lua", "p\nq\n")
    H.poll()
    eq({ "modified o.lua +1 -0 #1" }, H.pending())
  end)

  it("waits briefly for a report that arrives after the change", function()
    H.write("w.lua", "1\n")
    start()
    H.write("w.lua", "1\n2\n")
    H.poll(true)
    eq({}, H.pending(), "not the agent's yet")
    report(claude_edit("w.lua", "PostToolUse"))
    H.poll(true)
    eq({ "modified w.lua +1 -0 #1" }, H.pending())
  end)

  it("keeps Neovim's own writes the user's", function()
    H.write("n.lua", "1\n")
    start()
    report(claude_edit("n.lua"))
    H.edit("n.lua")
    H.change(1, 1, { "mine" })
    H.save()
    H.poll()
    eq({}, H.pending())
  end)
end)
