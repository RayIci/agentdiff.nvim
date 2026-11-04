local H = require("helpers")

local journal = require("agentdiff.core.journal")

describe("journal", function()
  local dir

  before_each(function()
    dir = H.state .. "/store"
    vim.fn.mkdir(dir, "p")
  end)

  it("records reports from many writers without losing any", function()
    for i = 1, 20 do
      journal.add(
        dir,
        { time = 1000 + i, harness = "claude", phase = "post", paths = { "f" .. i .. ".lua" } }
      )
    end
    local got = journal.reported(dir, 0)
    eq(20, vim.tbl_count(got))
    eq(1007, got["f7.lua"])
  end)

  it("ignores reports older than the window", function()
    journal.add(dir, { time = 1000, harness = "claude", phase = "pre", paths = { "a.lua" } })
    journal.add(dir, { time = 5000, harness = "claude", phase = "pre", paths = { "b.lua" } })
    eq({ ["b.lua"] = 5000 }, journal.reported(dir, 4000))
  end)

  it("consumes reports, keeping other paths of the same report", function()
    journal.add(dir, { time = 1000, harness = "claude", phase = "post", paths = { "a.lua", "b.lua" } })
    journal.take(dir, { "a.lua" }, 1100)
    eq({ ["b.lua"] = 1000 }, journal.reported(dir, 0))
  end)

  it("drops a late duplicate of a consumed report", function()
    journal.add(dir, { time = 1000, harness = "claude", phase = "pre", paths = { "a.lua" } })
    journal.take(dir, { "a.lua" }, 1200)
    journal.add(dir, { time = 1500, harness = "claude", phase = "post", paths = { "a.lua" } })
    eq({}, journal.reported(dir, 0), "the post of an edit already used")
    journal.add(
      dir,
      { time = 1200 + journal.dup_window + 1, harness = "claude", phase = "pre", paths = { "a.lua" } }
    )
    eq(1, vim.tbl_count(journal.reported(dir, 0)), "a later edit counts again")
  end)

  it("deletes old reports but remembers each harness's last report", function()
    journal.add(dir, { time = 1000, harness = "claude", phase = "post", paths = { "a.lua" } })
    journal.add(dir, { time = 2000, harness = "copilot", phase = "post", paths = { "b.lua" } })
    journal.gc(dir, 1000 + journal.report_ttl + 1)
    eq({ ["b.lua"] = 2000 }, journal.reported(dir, 0))
    eq({ claude = 1000, copilot = 2000 }, journal.last(dir))
  end)
end)

describe("attribution option", function()
  it("defaults to the hooks mode (Default mode)", function()
    local agentdiff = require("agentdiff")
    agentdiff.setup({
      root = H.project,
      state_dir = H.state .. "/agentdiff",
      poll_interval = 0,
      auto_start = false,
    })
    agentdiff.start()
    ok(agentdiff._test.wait_ready(5000), "ready")
    eq("hooks", agentdiff._test.session().opts.attribution)
    eq("hooks", require("agentdiff.attribution").active(agentdiff._test.session()).name)
  end)

  it("rejects an unknown mode (Unknown mode)", function()
    local ok_, err = pcall(require("agentdiff").setup, { attribution = "magic", auto_start = false })
    ok(not ok_, "setup failed")
    ok(tostring(err):find("magic", 1, true) and tostring(err):find("writer", 1, true), tostring(err))
  end)
end)
