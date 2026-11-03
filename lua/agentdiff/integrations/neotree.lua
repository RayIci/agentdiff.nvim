---neo-tree.nvim integration: a review mark on files with pending agent
---changes and on collapsed directories that contain one.
---
---  require("neo-tree").setup({
---    filesystem = {
---      components = { agentdiff = require("agentdiff.integrations.neotree").component },
---      renderers = require("agentdiff.integrations.neotree").renderers(),
---    },
---  })
---  require("agentdiff.integrations.neotree").setup()  -- refresh the tree on changes
---
---neo-tree is required only by renderers() and by the refresh in setup().
---@class AgentdiffNeotree
local M = {}

---The mark shown next to a changed file or directory.
M.icon = "󰚩 "

---neo-tree component: the review mark for a node, or nothing.
---@param _ table component config
---@param node table neo-tree node (needs `path`; directories also `is_expanded`)
---@return table
function M.component(_, node, _)
  local ok, st = pcall(require("agentdiff").path_status, node.path)
  if not ok or not st then
    return {}
  end
  if st == "dir" and node.is_expanded and node:is_expanded() then
    return {}
  end
  return { text = M.icon, highlight = st == "file" and "AgentdiffTreeFile" or "AgentdiffTreeDir" }
end

---neo-tree's default renderers with the `agentdiff` component placed right
---before `git_status`, for files and directories. Copied when called, so the
---rest of the layout follows neo-tree's own defaults.
---@return table
function M.renderers()
  local renderers = vim.deepcopy(require("neo-tree.defaults").renderers)
  for _, kind in ipairs({ "file", "directory" }) do
    for _, part in ipairs(renderers[kind] or {}) do
      if part[1] == "container" then
        local at = #part.content + 1
        for i, c in ipairs(part.content) do
          if c[1] == "git_status" then
            at = i
            break
          end
        end
        table.insert(part.content, at, { "agentdiff", zindex = 20, align = "right" })
      end
    end
  end
  return renderers
end

---Refresh neo-tree's filesystem source whenever pending changes change.
function M.setup()
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("agentdiff_neotree", { clear = true }),
    pattern = "AgentdiffChanged",
    callback = function()
      if package.loaded["neo-tree"] then
        pcall(function()
          require("neo-tree.sources.manager").refresh("filesystem")
        end)
      end
    end,
  })
end

return M
