---The `:Agentdiff` user command: one subcommand per action, with completion.
---@class AgentdiffCommand
local M = {}

local detect = require("agentdiff.detect.poller")
local util = require("agentdiff.core.util")

---The subcommand table for a public API table.
---@param api Agentdiff
---@return table<string, fun(range: integer[]?, args: string[])>
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
    hooks = function(_, args)
      local action = args[1] or "status"
      if action == "install" then
        api.hooks_install(args[2], args[3])
      elseif action == "uninstall" then
        api.hooks_uninstall(args[2], args[3])
      elseif action == "status" then
        api.hooks_status()
      else
        util.notify(
          "agentdiff: hooks install|uninstall|status [harness] [user|project]",
          vim.log.levels.ERROR
        )
      end
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

---Completion of the arguments of subcommands that take some: one list per
---argument position.
---@type table<string, fun(): string[][]>
M.arguments = {
  hooks = function()
    local names = require("agentdiff.harness").names()
    table.insert(names, 1, "all")
    return { { "install", "uninstall", "status" }, names, { "user", "project" } }
  end,
}

---Completion candidates for a `:Agentdiff` command line.
---@param subs table<string, function>
---@param lead string
---@param line string
---@return string[]
function M.complete(subs, lead, line)
  local words = vim.split(vim.trim(line), "%s+")
  if line:match("%s$") then
    words[#words + 1] = ""
  end
  local pos = #words - 1 -- 1 = the subcommand
  local candidates
  if pos <= 1 then
    candidates = vim.tbl_keys(subs)
    table.sort(candidates)
  else
    local args = M.arguments[words[2]]
    candidates = args and args()[pos - 1] or {}
  end
  return vim.tbl_filter(function(n)
    return n:find(lead, 1, true) == 1
  end, candidates)
end

---Create (or replace) the `:Agentdiff` command.
---@param subs table<string, fun(range: integer[]?, args: string[])>
function M.create(subs)
  vim.api.nvim_create_user_command("Agentdiff", function(cmd)
    local name = cmd.fargs[1] or "panel"
    local fn = subs[name]
    if not fn then
      return util.notify("agentdiff: unknown subcommand '" .. name .. "'", vim.log.levels.ERROR)
    end
    fn(cmd.range > 0 and { cmd.line1, cmd.line2 } or nil, vim.list_slice(cmd.fargs, 2))
  end, {
    nargs = "*",
    range = true,
    desc = "agentdiff: review agent changes",
    complete = function(lead, line)
      return M.complete(subs, lead, line)
    end,
  })
end

return M
