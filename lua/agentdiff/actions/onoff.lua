---Turning review on and off, persisted across restarts.
---
---One global file, `<state_dir>/enabled`: "on <epoch>" or "off <epoch>". The
---epoch changes every time review is turned on; each store remembers the epoch
---it was built in, and a store from before a disabled period is rebuilt from
---the disk, so nothing that changed while review was off shows as pending.
---@class AgentdiffOnOff
local M = {}

local config = require("agentdiff.config")
local store_mod = require("agentdiff.core.store")
local util = require("agentdiff.core.util")

---Start and stop of the review session, supplied by the entry point.
---@class AgentdiffLifecycle
---@field start fun()
---@field stop fun()

---@return string
local function state_file()
  return config.state_dir() .. "/enabled"
end

---@return boolean enabled
---@return string? epoch
function M.read()
  local t = util.read_file(state_file())
  if not t then
    return true, nil
  end
  local word, epoch = t:match("^(%a+)%s*(%d*)")
  return word ~= "off", (epoch ~= "" and epoch or nil)
end

---@param on boolean
local function write(on)
  local _, epoch = M.read()
  if on then
    epoch = tostring(util.now_ms())
  end
  util.write_file(state_file(), ("%s %s\n"):format(on and "on" or "off", epoch or ""))
end

---True when review is on (persisted across restarts).
---@return boolean
function M.enabled()
  return (M.read())
end

---The store to use for a project: rebuilt from the disk when it was built
---before review was last turned off.
---@param store AgentdiffStore
---@param root string
---@param opts AgentdiffOptions
---@param epoch string?
---@return AgentdiffStore
function M.fresh_store(store, root, opts, epoch)
  if not epoch then
    return store
  end
  local stored = vim.trim(util.read_file(store.dir .. "/epoch") or "")
  if stored == epoch then
    return store
  end
  store_mod.destroy(store)
  local fresh = store_mod.open(root, opts)
  util.write_file(fresh.dir .. "/epoch", epoch .. "\n")
  return fresh
end

---@param life AgentdiffLifecycle
function M.enable(life)
  write(true)
  life.start()
  util.notify("agentdiff: on")
end

---@param life AgentdiffLifecycle
function M.disable(life)
  write(false)
  life.stop()
  util.notify("agentdiff: off")
end

---@param life AgentdiffLifecycle
function M.toggle(life)
  if M.enabled() then
    M.disable(life)
  else
    M.enable(life)
  end
end

return M
