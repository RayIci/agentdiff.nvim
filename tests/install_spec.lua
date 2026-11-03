local H = require("helpers")

local claude = require("agentdiff.harness.claude")
local copilot = require("agentdiff.harness.copilot")
local settings = require("agentdiff.harness.settings")

---@return AgentdiffHarnessOpts
local function opts()
  local home = H.state .. "/home"
  vim.fn.mkdir(home, "p")
  return { home = home, root = H.project, state_dir = H.state .. "/agentdiff" }
end

local function read_json(file)
  local text = assert(H.read_abs(file), file)
  return vim.json.decode(text)
end

local function write_json(file, data)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  H.write_abs(file, vim.json.encode(data))
end

---Other settings and hooks a user already has.
local function existing()
  return {
    model = "opus",
    permissions = { allow = { "Bash(git status)" }, deny = {} },
    hooks = {
      PreToolUse = { { matcher = "Bash", hooks = { { type = "command", command = "my-guard.sh" } } } },
      Stop = { { hooks = { { type = "command", command = "notify-send done" } } } },
    },
  }
end

---@param data table
---@param event string
---@return table[] agentdiff's entries for that event
local function ours(data, event)
  return vim.tbl_filter(settings.ours, (data.hooks or {})[event] or {})
end

for _, scope in ipairs({ "user", "project" }) do
  describe("claude hook install (" .. scope .. " scope)", function()
    it("merges into existing settings and backs them up (Install into existing settings)", function()
      local o = opts()
      local file = claude.file(scope, o)
      write_json(file, existing())
      local original = H.read_abs(file)
      local ok_, msg = claude.install(scope, o)
      ok(ok_, msg)
      ok(msg:find("^installed in"), msg)
      local data = read_json(file)
      eq("opus", data.model)
      eq({ "Bash(git status)" }, data.permissions.allow)
      eq("my-guard.sh", data.hooks.PreToolUse[1].hooks[1].command, "the user's hook is kept first")
      eq(existing().hooks.Stop, data.hooks.Stop)
      eq(1, #ours(data, "PreToolUse"))
      eq(1, #ours(data, "PostToolUse"))
      local entry = ours(data, "PreToolUse")[1]
      eq(claude.matcher, entry.matcher)
      local cmd = entry.hooks[1].command
      ok(cmd:find(o.state_dir, 1, true), "the absolute store location is in the command: " .. cmd)
      ok(cmd:find(" claude ", 1, true) and cmd:match(" pre$"), cmd)
      eq(original, H.read_abs(file .. ".agentdiff.bak"))
      -- the empty list stays a list
      ok(H.read_abs(file):find('"deny": []', 1, true), H.read_abs(file))
    end)

    it("changes nothing when installed twice (Install twice)", function()
      local o = opts()
      local file = claude.file(scope, o)
      write_json(file, existing())
      claude.install(scope, o)
      local first = H.read_abs(file)
      local ok_, msg = claude.install(scope, o)
      ok(ok_ and msg:find("^already installed"), msg)
      eq(first, H.read_abs(file))
    end)

    it("removes only agentdiff's hooks (Uninstall)", function()
      local o = opts()
      local file = claude.file(scope, o)
      write_json(file, existing())
      claude.install(scope, o)
      local ok_, msg = claude.uninstall(scope, o)
      ok(ok_ and msg:find("^removed from"), msg)
      eq(existing(), read_json(file))
      eq(false, claude.status(o).installed)
      ok_, msg = claude.uninstall(scope, o)
      ok(ok_ and msg:find("^not installed"), msg)
    end)

    it("creates no file when uninstalling what isn't there", function()
      local o = opts()
      local ok_, msg = claude.uninstall(scope, o)
      ok(ok_ and msg:find("^not installed"), msg)
      eq(nil, vim.uv.fs_stat(claude.file(scope, o)))
      ok_, msg = copilot.uninstall(scope, o)
      ok(ok_ and msg:find("^not installed"), msg)
      eq(nil, vim.uv.fs_stat(copilot.file(scope, o)))
    end)

    it("creates the settings file when there is none", function()
      local o = opts()
      claude.install(scope, o)
      local data = read_json(claude.file(scope, o))
      eq({ "PostToolUse", "PreToolUse" }, vim.fn.sort(vim.tbl_keys(data.hooks)))
      eq({ claude.file(scope, o) }, claude.status(o).where)
      claude.uninstall(scope, o)
      eq({}, read_json(claude.file(scope, o)))
    end)
  end)

  describe("copilot hook install (" .. scope .. " scope)", function()
    it("writes its own hook file, beside the user's (Install into existing settings)", function()
      local o = opts()
      local file = copilot.file(scope, o)
      local other = vim.fs.dirname(file) .. "/mine.json"
      write_json(
        other,
        { version = 1, hooks = { sessionStart = { { type = "command", bash = "echo hi" } } } }
      )
      local before = H.read_abs(other)
      local ok_, msg = copilot.install(scope, o)
      ok(ok_ and msg:find("^installed in"), msg)
      local data = read_json(file)
      eq(1, data.version)
      eq(copilot.matcher, data.hooks.preToolUse[1].matcher)
      ok(data.hooks.preToolUse[1].bash:match(" pre$"), data.hooks.preToolUse[1].bash)
      ok(data.hooks.postToolUse[1].bash:match(" post$"), data.hooks.postToolUse[1].bash)
      eq(10, data.hooks.postToolUse[1].timeoutSec)
      eq(before, H.read_abs(other))
      eq({ installed = true, where = { file } }, copilot.status(o))
    end)

    it("changes nothing when installed twice (Install twice)", function()
      local o = opts()
      copilot.install(scope, o)
      local first = H.read_abs(copilot.file(scope, o))
      local ok_, msg = copilot.install(scope, o)
      ok(ok_ and msg:find("^already installed"), msg)
      eq(first, H.read_abs(copilot.file(scope, o)))
    end)

    it("removes its hook file (Uninstall)", function()
      local o = opts()
      copilot.install(scope, o)
      local ok_, msg = copilot.uninstall(scope, o)
      ok(ok_ and msg:find("^removed from"), msg)
      eq(nil, vim.uv.fs_stat(copilot.file(scope, o)))
      eq(false, copilot.status(o).installed)
    end)
  end)
end

describe("hook install safety", function()
  it("leaves a settings file that isn't valid JSON alone", function()
    local o = opts()
    local file = claude.file("user", o)
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    H.write_abs(file, "{ broken")
    local ok_, msg = claude.install("user", o)
    eq(false, ok_)
    ok(msg:find("not valid JSON"), msg)
    eq("{ broken", H.read_abs(file))
  end)

  it("quotes paths with spaces and quotes in the command", function()
    local cmd = settings.command("claude", "/tmp/it's here", "post")
    ok(cmd:find([['/tmp/it'\''s here']], 1, true), cmd)
  end)
end)

describe("hooks command", function()
  local saved_home

  before_each(function()
    saved_home = vim.env.HOME
    vim.env.HOME = opts().home
  end)

  after_each(function()
    vim.env.HOME = saved_home
  end)

  it("shows where the hook is and its last report (Status after an edit)", function()
    H.write("src/a.lua", "1\n")
    local agentdiff = H.start({ attribution = "hooks" })
    ok(agentdiff.hooks_install("claude"), "installed")
    local st = agentdiff.hooks_status({ silent = true })
    eq(true, st.claude.installed)
    eq(nil, st.claude.last_report)
    eq(false, st.copilot.installed)

    -- the agent edits a file: run the installed command as Claude Code would
    local data = read_json(vim.env.HOME .. "/.claude/settings.json")
    local function run(event)
      local entry = ours(data, event)[1]
      local payload = vim.json.encode({
        cwd = H.project,
        hook_event_name = event,
        tool_name = "Edit",
        tool_input = { file_path = H.path("src/a.lua") },
      })
      local r = vim.system({ "sh", "-c", entry.hooks[1].command }, { stdin = payload, text = true }):wait()
      eq(0, r.code)
      eq("", r.stdout .. r.stderr)
    end
    run("PreToolUse")
    H.write("src/a.lua", "1\n2\n")
    run("PostToolUse")

    st = agentdiff.hooks_status({ silent = true })
    eq({ vim.env.HOME .. "/.claude/settings.json" }, st.claude.where)
    ok(type(st.claude.last_report) == "number", "last report time")
    H.poll()
    eq({ "modified src/a.lua +1 -0 #1" }, H.pending())

    vim.cmd("Agentdiff hooks status")
    vim.cmd("Agentdiff hooks uninstall all")
    eq(false, agentdiff.hooks_status({ silent = true }).claude.installed)
  end)

  it("installs at project scope and rejects unknown names", function()
    local agentdiff = H.start()
    vim.cmd("Agentdiff hooks install copilot project")
    ok(vim.uv.fs_stat(H.path(".github/hooks/agentdiff.json")), "project hook file")
    eq(false, agentdiff.hooks_install("nope"))
    eq(false, agentdiff.hooks_install("claude", "galaxy"))
  end)

  it("completes subcommands and their arguments", function()
    H.start()
    local command = require("agentdiff.command")
    local subs = require("agentdiff").subcommands
    eq({ "keep", "keep_all", "keep_file" }, command.complete(subs, "ke", "Agentdiff ke"))
    eq({ "install", "uninstall", "status" }, command.complete(subs, "", "Agentdiff hooks "))
    eq({ "claude", "copilot" }, command.complete(subs, "c", "Agentdiff hooks install c"))
    eq({ "all", "claude", "copilot" }, command.complete(subs, "", "'<,'>Agentdiff hooks install "))
    eq({ "user", "project" }, command.complete(subs, "", "Agentdiff hooks install claude "))
    eq({}, command.complete(subs, "", "Agentdiff keep "))
  end)
end)
