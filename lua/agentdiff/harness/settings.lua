---Editing agent CLI configuration files: read JSON, let an adapter change it,
---write it back (keys sorted, two-space indent) after backing the original up
---once to `<file>.agentdiff.bak`. agentdiff's hook entries are recognised by
---the reporter's file name in their command.
---@class AgentdiffSettings
local M = {}

local uv = vim.uv

M.marker = "agentdiff-hook.lua"

local here = debug.getinfo(1, "S").source:sub(2)

---The plugin's root directory (where this copy of agentdiff is installed).
---@return string
function M.plugin_dir()
  return vim.fn.fnamemodify(here, ":p:h:h:h:h")
end

---@return string
function M.reporter()
  return M.plugin_dir() .. "/bin/" .. M.marker
end

---The Neovim executable for hook commands: an AppImage's `v:progpath` is a
---temporary mount, so its image file is used instead.
---@return string
function M.nvim()
  local appimage = vim.env.APPIMAGE
  if appimage and appimage ~= "" then
    return appimage
  end
  return vim.v.progpath
end

---@param s string
---@return string
local function quote(s)
  return "'" .. (s:gsub("'", [['\'']])) .. "'"
end

---The shell command a hook runs.
---@param harness string
---@param state_dir string
---@param phase "pre"|"post"
---@return string
function M.command(harness, state_dir, phase)
  return table.concat({
    quote(M.nvim()),
    "--headless -u NONE -i NONE -l",
    quote(M.reporter()),
    harness,
    quote(state_dir),
    phase,
  }, " ")
end

---True when a value (any nesting) holds agentdiff's hook command.
---@param v any
---@return boolean
function M.ours(v)
  if type(v) == "string" then
    return v:find(M.marker, 1, true) ~= nil
  elseif type(v) == "table" then
    for _, x in pairs(v) do
      if M.ours(x) then
        return true
      end
    end
  end
  return false
end

---@param file string
---@return table? data  nil when the file isn't valid JSON
---@return string? err
function M.read(file)
  local f = io.open(file, "rb")
  if not f then
    return vim.empty_dict()
  end
  local text = f:read("*a")
  f:close()
  if text:match("^%s*$") then
    return vim.empty_dict()
  end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, file .. " is not valid JSON; left unchanged"
  end
  return data
end

---@param file string
---@param data table
function M.write(file, data)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  local tmp = file .. ".agentdiff.tmp"
  local f = assert(io.open(tmp, "wb"))
  f:write(vim.json.encode(data, { indent = "  ", sort_keys = true }), "\n")
  f:close()
  assert(uv.fs_rename(tmp, file))
end

---Back the file up before its first change by agentdiff.
---@param file string
local function backup(file)
  local bak = file .. ".agentdiff.bak"
  if uv.fs_stat(file) and not uv.fs_stat(bak) then
    uv.fs_copyfile(file, bak)
  end
end

---Change a JSON file: `fn` gets a copy of its data and returns the new data,
---or nil to delete the file. Nothing is written when nothing changed.
---@param file string
---@param fn fun(data: table): table?
---@return boolean ok
---@return boolean|string changed_or_err
function M.update(file, fn)
  local data, err = M.read(file)
  if not data then
    return false, err or file
  end
  local new = fn(vim.deepcopy(data))
  if new == nil then
    if not uv.fs_stat(file) then
      return true, false
    end
    backup(file)
    os.remove(file)
    return true, true
  end
  if vim.deep_equal(new, data) then
    return true, false
  end
  local ok, werr = pcall(function()
    backup(file)
    M.write(file, new)
  end)
  if not ok then
    return false, tostring(werr)
  end
  return true, true
end

---Shorten a path under the home directory for messages.
---@param file string
---@return string
function M.display(file)
  return vim.fn.fnamemodify(file, ":~")
end

return M
