---Change events. In-process subscribers (the UI) register with on() and are
---called by emit(); changed() fires `User AgentdiffChanged` when the set of
---pending changes actually changed.
---@class AgentdiffEvents
local M = {}

---@type table<string, fun(...)[]>
local subscribers = {}

---Subscribe to an internal event ("refreshed": session, refreshed paths or nil).
---@param name string
---@param fn fun(...)
function M.on(name, fn)
  subscribers[name] = subscribers[name] or {}
  table.insert(subscribers[name], fn)
end

---@param name string
---@param ... any
function M.emit(name, ...)
  for _, fn in ipairs(subscribers[name] or {}) do
    fn(...)
  end
end

---Fire `User AgentdiffChanged` when the pending summary changed since last time.
---@param s AgentdiffSession
function M.changed(s)
  local parts = {}
  for _, p in ipairs(s.order) do
    local f = s.files[p]
    parts[#parts + 1] = ("%s:%s:%d:%d:%d"):format(p, f.status, #f.hunks, f.added, f.removed)
  end
  local sig = table.concat(parts, "|")
  if sig ~= s.signature then
    s.signature = sig
    vim.api.nvim_exec_autocmds("User", { pattern = "AgentdiffChanged", modeline = false })
  end
end

return M
