-- The public surface the refactor must keep exactly as it is.
describe("public surface", function()
  it("keeps every public function", function()
    local a = require("agentdiff")
    local fns = {}
    for k, v in pairs(a) do
      if type(v) == "function" and k:sub(1, 1) ~= "_" then
        fns[#fns + 1] = k
      end
    end
    table.sort(fns)
    eq({
      "claim",
      "disable",
      "enable",
      "enabled",
      "files",
      "hooks_install",
      "hooks_status",
      "hooks_uninstall",
      "keep",
      "keep_all",
      "keep_file",
      "next",
      "next_file",
      "open",
      "panel",
      "path_status",
      "prev",
      "prev_file",
      "reset",
      "resolve",
      "setup",
      "start",
      "status",
      "stop",
      "toggle",
      "toggle_overlay",
      "toggle_view",
      "undo",
      "undo_all",
      "undo_file",
    }, fns)
  end)

  it("keeps every subcommand", function()
    local subs = vim.tbl_keys(require("agentdiff").subcommands)
    table.sort(subs)
    eq({
      "disable",
      "enable",
      "hooks",
      "keep",
      "keep_all",
      "keep_file",
      "next",
      "next_file",
      "overlay",
      "panel",
      "prev",
      "prev_file",
      "refresh",
      "reset",
      "resolve",
      "status",
      "toggle",
      "undo",
      "undo_all",
      "undo_file",
      "view",
    }, subs)
  end)

  it("keeps every option and its default", function()
    local d = require("agentdiff.config").defaults
    eq(
      {
        attribution = "hooks",
        auto_start = true,
        claim_ttl = 10000,
        confirm = true,
        hint = true,
        keep_on_stage = true,
        keymaps = false,
        max_file_size = 1024 * 1024,
        max_files = 20000,
        panel = { view = "tree", position = "right", size = 40, icons = true },
        poll_interval = 1000,
        settle = 300,
      },
      (function()
        local c = vim.deepcopy(d)
        c.excludes = nil
        return c
      end)()
    )
    ok(vim.tbl_contains(d.excludes, "node_modules/"))
  end)

  it("keeps every highlight group", function()
    require("agentdiff").setup({ auto_start = false })
    for _, g in ipairs({
      "AgentdiffAdd",
      "AgentdiffDelete",
      "AgentdiffHint",
      "AgentdiffConflict",
      "AgentdiffTreeFile",
      "AgentdiffTreeDir",
      "AgentdiffPanelTitle",
      "AgentdiffPanelDir",
      "AgentdiffPanelAdded",
      "AgentdiffPanelRemoved",
      "AgentdiffPanelModified",
      "AgentdiffPanelCreated",
      "AgentdiffPanelDeleted",
      "AgentdiffPanelConflicted",
    }) do
      ok(next(vim.api.nvim_get_hl(0, { name = g })) ~= nil, g)
    end
  end)
end)
