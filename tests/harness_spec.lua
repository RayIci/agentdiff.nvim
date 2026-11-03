describe("harness registry", function()
  it("registers and returns adapters by name", function()
    local harness = require("agentdiff.harness")
    local fake = {
      name = "fake",
      parse = function(payload)
        return payload.file and { phase = "post", paths = { payload.file } } or nil
      end,
      install = function()
        return true
      end,
      uninstall = function()
        return true
      end,
      status = function()
        return { installed = false }
      end,
    }
    harness.register(fake)
    eq(fake, harness.get("fake"))
    ok(vim.tbl_contains(harness.names(), "fake"))
    eq({ phase = "post", paths = { "/p/x.lua" } }, harness.get("fake").parse({ file = "/p/x.lua" }))
    eq(nil, harness.get("nope"))
  end)
end)

describe("claude adapter", function()
  local claude = require("agentdiff.harness.claude")

  it("reads Edit payloads (Edit payload)", function()
    eq(
      { phase = "pre", paths = { "/p/src/a.lua" }, session = "s1" },
      claude.parse({
        session_id = "s1",
        cwd = "/p",
        hook_event_name = "PreToolUse",
        tool_name = "Edit",
        tool_input = { file_path = "/p/src/a.lua", old_string = "x", new_string = "y" },
      })
    )
  end)

  it("reads Write, MultiEdit and NotebookEdit, resolving relative paths", function()
    local function parse(tool, input)
      local r =
        claude.parse({ cwd = "/p", hook_event_name = "PostToolUse", tool_name = tool, tool_input = input })
      return r and r.paths
    end
    eq({ "/p/new.lua" }, parse("Write", { file_path = "new.lua", content = "" }))
    eq({ "/p/m.lua" }, parse("MultiEdit", { file_path = "/p/m.lua", edits = {} }))
    eq({ "/p/n.ipynb" }, parse("NotebookEdit", { notebook_path = "/p/n.ipynb" }))
    eq(
      "post",
      claude.parse({ hook_event_name = "PostToolUse", tool_name = "Write", tool_input = { file_path = "/x" } }).phase
    )
  end)

  it("ignores tools that don't edit files", function()
    eq(nil, claude.parse({ tool_name = "Bash", tool_input = { command = "sed -i s/a/b/ f" } }))
    eq(nil, claude.parse({ tool_name = "Read", tool_input = { file_path = "/p/a.lua" } }))
    eq(nil, claude.parse({}))
  end)
end)

describe("copilot adapter", function()
  local copilot = require("agentdiff.harness.copilot")

  it("reads camelCase payloads with JSON-string arguments (camelCase payload)", function()
    eq(
      { phase = "pre", paths = { "/p/src/a.lua" } },
      copilot.parse({
        cwd = "/p",
        toolName = "edit",
        toolArgs = '{"path":"src/a.lua","old_str":"x","new_str":"y"}',
      }, "preToolUse")
    )
  end)

  it("reads the files of a patch (Patch payload)", function()
    local patch = table.concat({
      "*** Begin Patch",
      "*** Update File: src/a.lua",
      "@@",
      "-old",
      "+new",
      "*** Add File: src/b.lua",
      "+hello",
      "*** End Patch",
    }, "\n")
    eq(
      { "/p/src/a.lua", "/p/src/b.lua" },
      copilot.parse({ cwd = "/p", toolName = "apply_patch", toolArgs = { input = patch } }).paths
    )
  end)

  it("reads VS Code-style payloads with Claude tool names", function()
    eq(
      { "/p/c.lua" },
      copilot.parse({
        cwd = "/p",
        hook_event_name = "PostToolUse",
        tool_name = "Edit",
        tool_input = { file_path = "/p/c.lua" },
      }).paths
    )
    eq(
      { "/p/d.lua" },
      copilot.parse({ cwd = "/p", toolName = "create", toolArgs = { filePath = "d.lua" } }).paths
    )
  end)

  it("ignores tools that don't edit files", function()
    eq(nil, copilot.parse({ toolName = "bash", toolArgs = { command = "ls" } }))
    eq(nil, copilot.parse({ toolName = "view", toolArgs = { path = "/p/a.lua" } }))
  end)
end)
