---Read-only views of the project's own git repository: the HEAD/stash and
---index watchers, git-produced changes (git-guard), discards toward HEAD, and
---staging-keeps. Nothing here ever writes to the project's .git.
---@class AgentdiffDetectGit
local M = {}

local baseline = require("agentdiff.core.baseline")
local merge = require("agentdiff.core.merge")
local session = require("agentdiff.core.session")
local state = require("agentdiff.core.state")
local store_mod = require("agentdiff.core.store")
local txt = require("agentdiff.core.text")
local util = require("agentdiff.core.util")

local uv = vim.uv

---@type string?
local guard_sig = nil
---@type string?
local index_sig = nil

---@param s AgentdiffSession
---@return string?
function M.project_gitdir(s)
  if s.project_gitdir == nil then
    local r = store_mod.project_git(s.root, { "rev-parse", "--absolute-git-dir" })
    s.project_gitdir = r.code == 0 and vim.trim(r.stdout or "") or false
  end
  return s.project_gitdir or nil
end

---Fingerprint of the project's HEAD and stash movement.
---@param s AgentdiffSession
---@return string
local function guard_signature(s)
  local gd = M.project_gitdir(s)
  if not gd then
    return ""
  end
  local parts = {}
  for _, f in ipairs({ "HEAD", "ORIG_HEAD", "logs/HEAD", "logs/refs/stash" }) do
    local st = uv.fs_stat(gd .. "/" .. f)
    parts[#parts + 1] = st and (st.mtime.sec .. "." .. st.mtime.nsec .. ":" .. st.size) or "-"
  end
  return table.concat(parts, "|")
end

---Fingerprint of the project's own index (`.git/index`), for staging.
---@param s AgentdiffSession
---@return string
local function index_signature(s)
  local gd = M.project_gitdir(s)
  local st = gd and uv.fs_stat(gd .. "/index")
  return st and (st.mtime.sec .. "." .. st.mtime.nsec .. ":" .. st.size) or ""
end

---Keep pending changes that were just staged in the project's index.
---@param s AgentdiffSession
---@return boolean changed
local function keep_staged(s)
  local paths = {}
  for _, p in ipairs(s.order) do
    if not s.conflicts[p] then
      paths[#paths + 1] = p
    end
  end
  if #paths == 0 or not M.project_gitdir(s) then
    return false
  end
  local staged = store_mod.index_contents(s.root, paths)
  local head = store_mod.head_contents(s.root, paths)
  local gone = {}
  for _, p in ipairs(paths) do
    if not staged[p] and not head[p] and not uv.fs_stat(session.abs(s, p)) then
      gone[#gone + 1] = p
    end
  end
  return baseline.keep_staged(s, paths, staged, head, store_mod.ever_tracked(s.root, gone))
end

---Apply staging-keeps to what is already pending when review starts:
---changes committed while Neovim was closed (or by an older version) must
---not stay pending forever.
---@param s AgentdiffSession
function M.reconcile(s)
  if s.opts.keep_on_stage and keep_staged(s) then
    state.refresh(s)
  end
end

---@param out string?
---@return table<string, boolean>
local function set0(out)
  local res = {}
  for item in (out or ""):gmatch("([^%z]+)") do
    res[item] = true
  end
  return res
end

---Paths whose disk state git itself just produced (content equals HEAD, or
---deleted and absent from HEAD).
---@param s AgentdiffSession
---@param paths string[]
---@return table<string, boolean>
function M.git_produced(s, paths)
  local res = {}
  if #paths == 0 then
    return res
  end
  local args = { "ls-tree", "-r", "-z", "--name-only", "HEAD", "--" }
  vim.list_extend(args, paths)
  local in_head = set0(store_mod.project_git(s.root, args).stdout)
  local dargs = { "diff", "--name-only", "-z", "--no-renames", "HEAD", "--" }
  vim.list_extend(dargs, paths)
  local differs = set0(store_mod.project_git(s.root, dargs).stdout)
  for _, p in ipairs(paths) do
    local exists = uv.fs_stat(session.abs(s, p)) ~= nil
    if exists then
      res[p] = in_head[p] == true and not differs[p]
    else
      res[p] = not in_head[p]
    end
  end
  return res
end

---Paths whose change only moves them back toward their HEAD content: a
---discard through git or a git client (`git restore`, `git checkout -- f`,
---lazygit's discard of a file or a hunk). Such a change satisfies
---merge3(observed, disk, HEAD) == HEAD; a change that moves away from HEAD
---(an agent edit, staged or not) doesn't.
---@param s AgentdiffSession
---@param paths string[]
---@return table<string, boolean>
function M.discarded(s, paths)
  local res = {}
  if #paths == 0 or not M.project_gitdir(s) then
    return res
  end
  local head = store_mod.head_contents(s.root, paths)
  local observed = s.store:read("observed", paths)
  for _, p in ipairs(paths) do
    local H = head[p] or nil
    local D = util.read_file(session.abs(s, p))
    local O = observed[p] or nil
    if H and D and D ~= O and not txt.is_whole(s, H, D, O) then
      local m = merge.merge3(merge.lines(O), merge.lines(D), merge.lines(H))
      res[p] = merge.join(m) == H
    end
  end
  return res
end

---Take the current HEAD/stash and index fingerprints as the starting point.
---@param s AgentdiffSession
function M.start(s)
  guard_sig = guard_signature(s)
  index_sig = index_signature(s)
end

function M.stop()
  guard_sig, index_sig = nil, nil
end

---What moved in the project's repository since the last call.
---@param s AgentdiffSession
---@return { guard_moved: boolean, index_moved: boolean }
function M.observe(s)
  local g, i = guard_signature(s), index_signature(s)
  local moved = {
    guard_moved = guard_sig ~= nil and g ~= guard_sig,
    index_moved = index_sig ~= nil and i ~= index_sig,
  }
  guard_sig, index_sig = g, i
  return moved
end

---Staging keeps, after a poll's changes are attributed (so an agent edit
---staged in the same instant is kept too).
---@param s AgentdiffSession
---@param moved { index_moved: boolean }
function M.after_poll(s, moved)
  if moved.index_moved and s.opts.keep_on_stage and keep_staged(s) then
    state.refresh(s)
  end
end

return M
