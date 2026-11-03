---Helpers shared by the actions: the active session and the file an action
---applies to.
---@class AgentdiffActionsCommon
local M = {}

local buffers = require("agentdiff.editor.buffers")
local session = require("agentdiff.core.session")
local state = require("agentdiff.core.state")
local util = require("agentdiff.core.util")

---@class AgentdiffActionOpts
---@field scope? "hunk"|"file"|"all"
---@field range? integer[]   1-based {first, last} line, for scope "hunk"
---@field path? string       project-relative path (default: current buffer)
---@field force? boolean     skip the keep-all / undo-all confirmation

---@return AgentdiffSession?
function M.active()
  local s = session.get()
  if not s or not s.ready then
    util.notify("agentdiff: not active yet", vim.log.levels.WARN)
    return nil
  end
  buffers.flush(s)
  return s
end

---@param s AgentdiffSession
---@param path string?
---@return string? rel
---@return AgentdiffFile? file
function M.target(s, path)
  -- From a side-by-side baseline window, act on the file it shows.
  local rel = path or vim.b.agentdiff_baseline_of or session.rel_of_buf(s, vim.api.nvim_get_current_buf())
  if not rel then
    return nil, nil
  end
  local f = state.compute(s, rel)
  s.files[rel] = f
  return rel, f
end

---The current buffer's 0-based cursor row (or the paired file's, from a baseline view).
---@return integer
function M.cursor_row()
  return vim.api.nvim_win_get_cursor(0)[1] - 1
end

return M
