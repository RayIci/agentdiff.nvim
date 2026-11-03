---Claims from tools: the next disk changes to these paths are the user's.
---@class AgentdiffActionsClaim
local M = {}

local claims = require("agentdiff.core.claims")
local session = require("agentdiff.core.session")
local util = require("agentdiff.core.util")

---Mark the next disk changes of these paths (absolute or project-relative) as
---the user's, e.g. right before or after a file explorer renames them. A path
---that is an existing directory claims every file under it.
---@param paths string[]
function M.claim(paths)
  local s = session.get()
  if not s then
    return
  end
  local rels = {}
  local function add(abs)
    local rel = util.relative(s.root, vim.fs.normalize(abs))
    if rel then
      rels[#rels + 1] = rel
    end
  end
  for _, p in ipairs(paths) do
    local abs = vim.fs.normalize(p:sub(1, 1) == "/" and p or session.abs(s, p)):gsub("/$", "")
    add(abs)
    local st = vim.uv.fs_stat(abs)
    if st and st.type == "directory" then
      for name, kind in vim.fs.dir(abs, { depth = math.huge }) do
        if kind == "file" then
          add(abs .. "/" .. name)
        end
      end
    end
  end
  claims.add(s.store, rels)
end

return M
