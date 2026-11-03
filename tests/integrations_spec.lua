local H = require("helpers")

local function node(rel, expanded)
  return {
    path = H.path(rel),
    is_expanded = function()
      return expanded
    end,
  }
end

describe("neo-tree integration", function()
  it("marks a changed file and nothing else (Component marks a changed file)", function()
    H.write("src/main.lua", "a\n")
    H.write("src/other.lua", "o\n")
    H.start()
    H.write("src/main.lua", "agent\n")
    H.poll()
    local nt = require("agentdiff.integrations.neotree")
    eq({ text = nt.icon, highlight = "AgentdiffTreeFile" }, nt.component({}, node("src/main.lua"), {}))
    eq({}, nt.component({}, node("src/other.lua"), {}))
  end)

  it("marks a collapsed directory but not an expanded one (Expanded directory)", function()
    H.write("src/main.lua", "a\n")
    H.start()
    H.write("src/main.lua", "agent\n")
    H.poll()
    local nt = require("agentdiff.integrations.neotree")
    eq({ text = nt.icon, highlight = "AgentdiffTreeDir" }, nt.component({}, node("src", false), {}))
    eq({}, nt.component({}, node("src", true), {}))
  end)

  it("adds the component before git_status in neo-tree's default renderers", function()
    package.loaded["neo-tree.defaults"] = {
      renderers = {
        file = { { "icon" }, { "container", content = { { "name" }, { "git_status" } } } },
        directory = { { "icon" }, { "container", content = { { "name" }, { "git_status" } } } },
      },
    }
    local r = require("agentdiff.integrations.neotree").renderers()
    package.loaded["neo-tree.defaults"] = nil
    eq(
      { "name", "agentdiff", "git_status" },
      vim.tbl_map(function(c)
        return c[1]
      end, r.file[2].content)
    )
    eq("agentdiff", r.directory[2].content[2][1])
  end)

  it("refreshes neo-tree when pending changes change", function()
    local refreshed = {}
    package.loaded["neo-tree"] = {}
    package.loaded["neo-tree.sources.manager"] = {
      refresh = function(src)
        refreshed[#refreshed + 1] = src
      end,
    }
    require("agentdiff.integrations.neotree").setup()
    vim.api.nvim_exec_autocmds("User", { pattern = "AgentdiffChanged" })
    package.loaded["neo-tree"], package.loaded["neo-tree.sources.manager"] = nil, nil
    eq({ "filesystem" }, refreshed)
  end)
end)

describe("oil integration", function()
  it("reads every url field of oil actions", function()
    eq(
      { "/p/a.lua", "/p/b.lua", "/p/c.lua" },
      require("agentdiff.integrations.oil").paths({
        { type = "move", src_url = "oil:///p/a.lua", dest_url = "oil:///p/b.lua" },
        { type = "create", url = "oil:///p/c.lua" },
        { type = "delete", url = "oil-trash:///p/old.lua" },
      })
    )
  end)

  it("claims oil's file actions (Rename in oil)", function()
    H.write("a.lua", "a\n")
    H.start()
    require("agentdiff.integrations.oil").setup()
    local actions =
      { { type = "move", src_url = "oil://" .. H.path("a.lua"), dest_url = "oil://" .. H.path("b.lua") } }
    vim.api.nvim_exec_autocmds("User", { pattern = "OilActionsPre", data = { actions = actions } })
    os.rename(H.path("a.lua"), H.path("b.lua"))
    vim.api.nvim_exec_autocmds("User", { pattern = "OilActionsPost", data = { actions = actions } })
    H.poll()
    eq({}, H.pending())
  end)
end)

describe("grug-far integration", function()
  it("claims each file before grug-far edits it (Project-wide replace)", function()
    H.write("x.lua", "foo\n")
    H.write("y.lua", "foo\n")
    H.start()
    local hook = require("agentdiff.integrations.grug_far").on_before_edit_file
    local statuses = {}
    for _, f in ipairs({ "x.lua", "y.lua" }) do
      hook(function(st)
        statuses[#statuses + 1] = st
      end, { path = f })
      H.write(f, "bar\n") -- grug-far's edit
    end
    eq({ "success", "success" }, statuses, "grug-far's edits proceed")
    H.poll()
    eq({}, H.pending())
  end)
end)

describe("integrations stay optional", function()
  it("loads no integration and no other plugin by default (Not loaded by default)", function()
    for name in pairs(package.loaded) do
      if name:match("^agentdiff%.integrations") then
        package.loaded[name] = nil
      end
    end
    H.start()
    for name in pairs(package.loaded) do
      ok(not name:match("^agentdiff%.integrations"), name .. " is loaded")
    end
    for _, p in ipairs({ "neo-tree", "oil", "grug-far" }) do
      eq(nil, package.loaded[p], p .. " is loaded")
    end
  end)

  it("requires fine without the other plugin installed (Other plugin absent)", function()
    for _, m in ipairs({ "neotree", "oil", "grug_far" }) do
      ok(pcall(require, "agentdiff.integrations." .. m), m)
    end
    for _, p in ipairs({ "neo-tree", "oil", "grug-far" }) do
      eq(nil, package.loaded[p], p .. " got required")
    end
    H.write("a.lua", "a\n")
    H.start()
    require("agentdiff.integrations.neotree").setup()
    vim.api.nvim_exec_autocmds("User", { pattern = "AgentdiffChanged" })
    H.write("a.lua", "agent\n")
    H.poll()
    eq({ "modified a.lua +1 -1 #1" }, H.pending(), "agentdiff keeps working")
  end)
end)
