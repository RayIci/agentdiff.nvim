-- The dependency rule: a module may require only modules on its own level or
-- below (see docs/architecture.md). Integrations may require only the public
-- `agentdiff` module.
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local root = repo .. "/lua/agentdiff"

local levels = {
  { 0, "^core%." },
  { 0, "^config$" },
  { 1, "^attribution$" },
  { 1, "^attribution%." },
  { 1, "^harness$" },
  { 1, "^harness%." },
  { 2, "^detect%." },
  { 2, "^editor%." },
  { 3, "^ui%." },
  { 4, "^actions%." },
  { 5, "^init$" },
  { 5, "^command$" },
  { 5, "^keymaps$" },
  { 6, "^integrations%." },
  -- flat modules not moved yet, at the level they are moving to
}

---Level of a module name relative to agentdiff ("core.merge", "init", …).
local function level(name)
  for _, l in ipairs(levels) do
    if name:match(l[2]) then
      return l[1]
    end
  end
  return nil
end

---Every require edge: { from = "core.state", to = "ui.overlay", file = … }.
local function edges()
  local out = {}
  for name, kind in vim.fs.dir(root, { depth = math.huge }) do
    if kind == "file" and name:match("%.lua$") then
      local mod = name:gsub("%.lua$", ""):gsub("/init$", ".init"):gsub("/", ".")
      if mod == "init" or mod:match("%.init$") then
        mod = mod == "init" and "init" or mod
      end
      -- code only: usage examples in comments are not dependencies
      local code = vim.tbl_filter(function(l)
        return not l:match("^%s*%-%-")
      end, vim.fn.readfile(root .. "/" .. name))
      local text = table.concat(code, "\n")
      for to in text:gmatch('require%("agentdiff%.([%w_%.]+)"%)') do
        out[#out + 1] = { from = mod, to = to, file = name }
      end
      if text:find('require%("agentdiff"%)') then
        out[#out + 1] = { from = mod, to = "init", file = name }
      end
    end
  end
  return out
end

-- Upward dependencies that still exist; each refactor step removes some.
local allowed = {
  -- ALLOW-LIST (emptied by the end of the refactor)
}

describe("layers", function()
  it("only requires modules on the same level or below", function()
    local bad = {}
    for _, e in ipairs(edges()) do
      local lf, lt = level(e.from), level(e.to)
      ok(lf ~= nil, "unknown level for module agentdiff." .. e.from .. " (" .. e.file .. ")")
      ok(lt ~= nil, "unknown level for required module agentdiff." .. e.to .. " (from " .. e.file .. ")")
      local key = e.from .. " -> " .. e.to
      local upward = lt > lf or (lf == 6 and e.to ~= "init")
      if upward and not allowed[key] then
        bad[#bad + 1] = key
      end
    end
    table.sort(bad)
    eq({}, bad, "upward dependencies")
  end)
end)
