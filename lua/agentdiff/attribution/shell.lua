---Recognising Ex command lines that run shell commands able to write files
---(`:!cmd`, `:{range}!filter`, `:r !cmd`, `:w !cmd`), behind any modifiers.
---Changes made by such commands are the user's.
---@class AgentdiffShell
local M = {}

local modifiers = {
  "aboveleft",
  "belowright",
  "botright",
  "browse",
  "confirm",
  "hide",
  "keepalt",
  "keepjumps",
  "keepmarks",
  "keeppatterns",
  "leftabove",
  "legacy",
  "lockmarks",
  "noautocmd",
  "noswapfile",
  "rightbelow",
  "sandbox",
  "silent",
  "tab",
  "topleft",
  "unsilent",
  "verbose",
  "vertical",
  "vim9cmd",
}

---@param w string
---@return boolean
local function is_modifier(w)
  if #w < 2 then
    return false
  end
  for _, m in ipairs(modifiers) do
    if m:sub(1, #w) == w then
      return true
    end
  end
  return false
end

---True when an Ex command line runs a shell command that can write files.
---@param cmdline string
---@return boolean
function M.is_shell_cmdline(cmdline)
  local s = cmdline:gsub("^[%s:]*", "")
  -- strip command modifiers (`:silent`, `:keepalt`, `:5verbose`, …)
  while true do
    local w, rest = s:match("^%d*(%a+)!?%s+(.*)$")
    if w and is_modifier(w) then
      s = rest
    else
      break
    end
  end
  -- strip a leading range: numbers, marks, patterns, %, $, ., +/- offsets, commas
  s = s:gsub("^[%d%s,;%.%$%%'<>%+%-]*", "")
  if s:sub(1, 1) == "!" then
    return true
  end
  return s:match("^r[ead]*%s*!") ~= nil or s:match("^w[rite]*%s+!") ~= nil -- `:w !cmd`, not the forced write `:w!`
end

return M
