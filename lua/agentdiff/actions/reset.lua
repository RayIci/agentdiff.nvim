---Reset: forget every pending change of the current project and start over
---from its current files. Other projects' stores are untouched.
---@class AgentdiffReset
local M = {}

local session = require("agentdiff.core.session")
local store_mod = require("agentdiff.core.store")
local util = require("agentdiff.core.util")

---Asks first unless `opts.force` or `confirm = false`.
---@param opts { force: boolean? }?
---@param life AgentdiffLifecycle
function M.reset(opts, life)
  local s = session.get()
  if not s then
    return util.notify("agentdiff: not active")
  end
  local force = (opts and opts.force) or not s.opts.confirm
  local question = ("Forget all pending changes of %s and start over from its current files?"):format(s.root)
  if not force and vim.fn.confirm(question, "&Yes\n&No", 2) ~= 1 then
    return
  end
  local store, root = s.store, s.root
  life.stop()
  store_mod.destroy(store)
  life.start()
  util.notify("agentdiff: reset " .. root)
end

return M
