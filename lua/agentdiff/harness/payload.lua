---Reading hook payloads defensively: field names differ between CLIs and
---between a CLI's own and its VS Code-compatible formats.
---@class AgentdiffPayload
local M = {}

---@param p table
---@return string?
function M.tool(p)
  local t = p.tool_name or p.toolName
  return type(t) == "string" and t or nil
end

---Tool arguments as a table (decoding a JSON string when needed).
---@param p table
---@return table
function M.args(p)
  local a = p.tool_input or p.toolArgs or p.tool_args or p.toolInput
  if type(a) == "string" then
    local ok, decoded = pcall(vim.json.decode, a)
    a = ok and type(decoded) == "table" and decoded or { patch = a }
  end
  return type(a) == "table" and a or {}
end

---"pre" or "post", from the payload's event name or the event the hook was
---installed for.
---@param p table
---@param hint? string
---@return "pre"|"post"
function M.phase(p, hint)
  local e = p.hook_event_name or p.hookEventName or hint or ""
  return e:lower():find("pre", 1, true) and "pre" or "post"
end

local path_keys = { "file_path", "path", "filePath", "filename", "notebook_path", "file" }
local patch_keys = { "command", "patch", "input", "diff" }

---Files named in a patch: `*** Update/Add/Delete File: x`, `*** Move to: x`,
---and unified-diff `+++ b/x` / `--- a/x` headers.
---@param text string
---@return string[]
function M.patch_paths(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local p = line:match("^%*%*%* %a+ File: (.-)%s*$")
      or line:match("^%*%*%* Move to: (.-)%s*$")
      or line:match("^%+%+%+ b/(.-)%s*$")
      or line:match("^%-%-%- a/(.-)%s*$")
    if p and p ~= "" and p ~= "/dev/null" then
      out[#out + 1] = p
    end
  end
  return out
end

---Absolute, normalized, de-duplicated paths named by tool arguments.
---@param args table
---@param cwd? string
---@return string[]
function M.paths(args, cwd)
  local raw = {}
  for _, k in ipairs(path_keys) do
    if type(args[k]) == "string" and args[k] ~= "" then
      raw[#raw + 1] = args[k]
    end
  end
  if #raw == 0 then
    for _, k in ipairs(patch_keys) do
      if type(args[k]) == "string" then
        vim.list_extend(raw, M.patch_paths(args[k]))
      end
    end
  end
  local seen, out = {}, {}
  for _, p in ipairs(raw) do
    if p:sub(1, 1) ~= "/" and cwd then
      p = cwd .. "/" .. p
    end
    p = vim.fs.normalize(p)
    if not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

---A report for a payload whose tool is in `tools`, or nil.
---@param p table
---@param tools table<string, true>
---@param hint? string  the event the hook was installed for
---@return AgentdiffHarnessReport?
function M.report(p, tools, hint)
  local tool = M.tool(p)
  if not tool or not tools[tool] then
    return nil
  end
  local paths = M.paths(M.args(p), type(p.cwd) == "string" and p.cwd or nil)
  if #paths == 0 then
    return nil
  end
  local session = p.session_id or p.sessionId
  return { phase = M.phase(p, hint), paths = paths, session = type(session) == "string" and session or nil }
end

return M
