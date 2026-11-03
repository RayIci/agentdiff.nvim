---Read-only views of the pending changes for statuslines and file trees.
---@class AgentdiffStatus
local M = {}

local positions = require("agentdiff.core.positions")
local session = require("agentdiff.core.session")
local util = require("agentdiff.core.util")

---Statusline summary: "3 files · 7 changes", or "" when nothing is pending.
---@return string
function M.status()
  local s = session.get()
  if not s or #s.order == 0 then
    return ""
  end
  local nf, nc = #s.order, positions.count(s)
  return ("%d %s · %d %s"):format(nf, nf == 1 and "file" or "files", nc, nc == 1 and "change" or "changes")
end

---@type { sig: string?, root: string?, files: table<string, true>, dirs: table<string, true> }
local status_cache = { files = {}, dirs = {} }

---Review status of a path, for file trees: "file" when the file has pending
---changes (created and deleted files included), "dir" when a directory
---contains such a file at any depth, nil otherwise. Cheap: answered from sets
---rebuilt only when pending changes change.
---@param path string absolute, or relative to the project root
---@return "file"|"dir"|nil
function M.path_status(path)
  local s = session.get()
  if not s or #s.order == 0 then
    return nil
  end
  if status_cache.sig ~= s.signature or status_cache.root ~= s.root then
    local files, dirs = {}, {}
    for _, p in ipairs(s.order) do
      files[p] = true
      local d = vim.fs.dirname(p)
      while d and d ~= "." and d ~= "" and not dirs[d] do
        dirs[d] = true
        d = vim.fs.dirname(d)
      end
    end
    dirs[""] = true -- the project root contains them all
    status_cache = { sig = s.signature, root = s.root, files = files, dirs = dirs }
  end
  local abs = path:sub(1, 1) == "/" and vim.fs.normalize(path) or session.abs(s, path)
  abs = abs:gsub("/$", "")
  local rel = abs == s.root and "" or util.relative(s.root, abs)
  if not rel then
    return nil
  end
  if status_cache.files[rel] then
    return "file"
  elseif status_cache.dirs[rel] then
    return "dir"
  end
  return nil
end

---Pending files in navigation order (read-only copies).
---@return AgentdiffFile[]
function M.files()
  local s = session.get()
  if not s then
    return {}
  end
  local out = {}
  for _, p in ipairs(s.order) do
    out[#out + 1] = vim.deepcopy(s.files[p])
  end
  return out
end

return M
