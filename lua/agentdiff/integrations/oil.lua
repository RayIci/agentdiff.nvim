---oil.nvim integration: oil creates, moves, copies and deletes files on disk
---itself, so its file actions are claimed (before and after) and never shown
---as agent changes.
---
---  require("agentdiff.integrations.oil").setup()
---@class AgentdiffOil
local M = {}

---Paths touched by a list of oil actions (oil:// URLs of the files adapter;
---other adapters, such as trash, are ignored).
---@param actions table[]?
---@return string[]
function M.paths(actions)
  local paths = {}
  for _, a in ipairs(actions or {}) do
    -- read the fields by key: a move has no `url`, so ipairs over the three
    -- would stop at that nil
    for _, key in ipairs({ "url", "src_url", "dest_url" }) do
      local url = a[key]
      local p = type(url) == "string" and url:match("^oil://(.*)$")
      if p then
        paths[#paths + 1] = p
      end
    end
  end
  return paths
end

---Claim the paths of every oil action, on OilActionsPre and OilActionsPost.
function M.setup()
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("agentdiff_oil", { clear = true }),
    pattern = { "OilActionsPre", "OilActionsPost" },
    callback = function(ev)
      require("agentdiff").claim(M.paths(ev.data and ev.data.actions))
    end,
  })
end

return M
