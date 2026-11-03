---grug-far.nvim integration: grug-far rewrites files on disk, so each one is
---claimed right before it is edited and never shown as an agent change.
---
---  require("grug-far").setup({
---    hooks = { on_before_edit_file = require("agentdiff.integrations.grug_far").on_before_edit_file },
---  })
---@class AgentdiffGrugFar
local M = {}

---grug-far's `hooks.on_before_edit_file`: claim the file, then let grug-far go on.
---@param on_finish fun(status?: string, err?: string)
---@param file { path: string }
function M.on_before_edit_file(on_finish, file)
  pcall(function()
    require("agentdiff").claim({ vim.fn.fnamemodify(file.path, ":p") })
  end)
  on_finish("success")
end

return M
