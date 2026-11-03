---The agent journal: files agent hooks reported as edited, per project store.
---
---Layout of `<store>/agent/`:
---  <ms>-<pid>-<n>.json   one report each: { time, harness, phase, paths, session? }
---                        (paths are project-relative; one file per report, so
---                        concurrent hook processes never contend)
---  taken.json            path → when a report for it was last consumed
---  last.json             harness → time of its newest report (for status)
---@class AgentdiffJournal
local M = {}

local util = require("agentdiff.core.util")

local uv = vim.uv

---Reports older than this are deleted by gc().
M.report_ttl = 60000
---After a path's reports are consumed, reports for it this soon after are
---late duplicates (the "post" of an edit whose "pre" was already used).
M.dup_window = 2000

---@class AgentdiffReport
---@field time integer      wall-clock ms
---@field harness string
---@field phase "pre"|"post"
---@field paths string[]    project-relative
---@field session? string

---@param store_dir string
---@return string
function M.dir(store_dir)
  return store_dir .. "/agent"
end

---@param path string
---@return table
local function read_json(path)
  local data = util.read_file(path)
  local ok, v = pcall(vim.json.decode, data or "")
  return ok and type(v) == "table" and v or {}
end

---@param path string
---@param v table
local function write_json(path, v)
  local tmp = path .. ".tmp" .. vim.fn.getpid()
  util.write_file(tmp, vim.json.encode(v))
  uv.fs_rename(tmp, path)
end

local seq = 0

---Record a report (written atomically: temp file, then rename).
---@param store_dir string
---@param report AgentdiffReport
function M.add(store_dir, report)
  local dir = M.dir(store_dir)
  vim.fn.mkdir(dir, "p")
  report.time = report.time or util.now_ms()
  seq = seq + 1
  local name = ("%d-%d-%d.json"):format(report.time, vim.fn.getpid(), seq)
  write_json(dir .. "/" .. name, report)
  local last = read_json(dir .. "/last.json")
  if (last[report.harness] or 0) < report.time then
    last[report.harness] = report.time
    write_json(dir .. "/last.json", last)
  end
end

---@param dir string
---@param fn fun(file: string, r: AgentdiffReport)
local function each(dir, fn)
  if not uv.fs_stat(dir) then
    return
  end
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("^%d+%-%d+%-%d+%.json$") then
      local r = read_json(dir .. "/" .. name)
      if type(r.paths) == "table" and type(r.time) == "number" then
        fn(dir .. "/" .. name, r)
      end
    end
  end
end

---Paths with a live report: path → newest report time, ignoring reports
---older than `since` and late duplicates of consumed ones.
---@param store_dir string
---@param since integer  wall-clock ms
---@return table<string, integer>
function M.reported(store_dir, since)
  local dir = M.dir(store_dir)
  local taken = read_json(dir .. "/taken.json")
  local res = {}
  each(dir, function(_, r)
    if r.time >= since then
      for _, p in ipairs(r.paths) do
        local t = taken[p]
        if not (t and r.time <= t + M.dup_window) and (res[p] or 0) < r.time then
          res[p] = r.time
        end
      end
    end
  end)
  return res
end

---Consume the reports of these paths (they covered one change each).
---@param store_dir string
---@param paths string[]
---@param now integer
function M.take(store_dir, paths, now)
  if #paths == 0 then
    return
  end
  local dir = M.dir(store_dir)
  local set = {}
  for _, p in ipairs(paths) do
    set[p] = true
  end
  each(dir, function(file, r)
    local rest = vim.tbl_filter(function(p)
      return not set[p]
    end, r.paths)
    if #rest == 0 then
      os.remove(file)
    elseif #rest < #r.paths then
      r.paths = rest
      write_json(file, r)
    end
  end)
  local taken = read_json(dir .. "/taken.json")
  for _, p in ipairs(paths) do
    taken[p] = now
  end
  write_json(dir .. "/taken.json", taken)
end

---Delete reports (and consumption marks) older than `ttl` ms.
---@param store_dir string
---@param now integer
---@param ttl? integer
function M.gc(store_dir, now, ttl)
  ttl = ttl or M.report_ttl
  local dir = M.dir(store_dir)
  each(dir, function(file, r)
    if now - r.time > ttl then
      os.remove(file)
    end
  end)
  local taken = read_json(dir .. "/taken.json")
  local changed = false
  for p, t in pairs(taken) do
    if now - t > ttl then
      taken[p] = nil
      changed = true
    end
  end
  if changed then
    write_json(dir .. "/taken.json", taken)
  end
end

---Time of the newest report per harness (survives consumption and gc).
---@param store_dir string
---@return table<string, integer>
function M.last(store_dir)
  return read_json(M.dir(store_dir) .. "/last.json")
end

return M
