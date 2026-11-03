---The `:Agentdiff` user command: one subcommand per action, with completion.
---@class AgentdiffCommand
local M = {}

local detect = require("agentdiff.detect.poller")
local util = require("agentdiff.core.util")

---The subcommand table for a public API table.
---@param api Agentdiff
---@return table<string, fun(range: integer[]?)>
function M.subcommands(api)
  return {
    next = function()
      api.next()
    end,
    prev = function()
      api.prev()
    end,
    next_file = function()
      api.next_file()
    end,
    prev_file = function()
      api.prev_file()
    end,
    keep = function(range)
      api.keep({ range = range })
    end,
    undo = function(range)
      api.undo({ range = range })
    end,
    keep_file = function()
      api.keep_file()
    end,
    undo_file = function()
      api.undo_file()
    end,
    keep_all = function()
      api.keep_all()
    end,
    undo_all = function()
      api.undo_all()
    end,
    panel = function()
      api.panel()
    end,
    view = function()
      api.toggle_view()
    end,
    overlay = function()
      api.toggle_overlay()
    end,
    resolve = function()
      api.resolve()
    end,
    refresh = function()
      detect.now("poll")
    end,
    enable = function()
      api.enable()
    end,
    disable = function()
      api.disable()
    end,
    toggle = function()
      api.toggle()
    end,
    reset = function()
      api.reset()
    end,
    status = function()
      if not api.enabled() then
        return util.notify("agentdiff: off")
      end
      local st = api.status()
      util.notify(st ~= "" and st or "agentdiff: nothing pending")
    end,
  }
end

---Create (or replace) the `:Agentdiff` command.
---@param subs table<string, fun(range: integer[]?)>
function M.create(subs)
  vim.api.nvim_create_user_command("Agentdiff", function(cmd)
    local name = cmd.fargs[1] or "panel"
    local fn = subs[name]
    if not fn then
      return util.notify("agentdiff: unknown subcommand '" .. name .. "'", vim.log.levels.ERROR)
    end
    fn(cmd.range > 0 and { cmd.line1, cmd.line2 } or nil)
  end, {
    nargs = "?",
    range = true,
    desc = "agentdiff: review agent changes",
    complete = function(lead)
      local names = vim.tbl_keys(subs)
      table.sort(names)
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, names)
    end,
  })
end

return M
