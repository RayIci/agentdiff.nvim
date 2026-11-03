---Text helpers shared by review state, baseline updates and actions: the
---line model (see core/merge.lua), buffer contents in display space, and the
---"reviewed as a whole file" rule.
---@class AgentdiffText
local M = {}

local merge = require("agentdiff.core.merge")

---@param s AgentdiffSession
---@param ... string?
---@return boolean
function M.is_whole(s, ...)
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t ~= nil and (#t > s.opts.max_file_size or merge.is_binary(t)) then
      return true
    end
  end
  return false
end

---@param buf integer
---@return boolean
local function is_dos(buf)
  return vim.bo[buf].fileformat == "dos"
end

---Buffer content as display-space lines (a trailing "" when the buffer will
---be written with a final newline).
---@param buf integer
---@return string[]
function M.buf_lines(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local empty = #lines == 1
    and lines[1] == ""
    and vim.api.nvim_buf_call(buf, function()
        return vim.fn.line2byte(vim.fn.line("$") + 1)
      end)
      == -1
  if empty then
    return { "" }
  end
  if vim.bo[buf].eol or (vim.bo[buf].fixeol and not vim.bo[buf].binary) then
    lines[#lines + 1] = ""
  end
  return lines
end

---Disk text → display-space lines for a buffer.
---@param buf integer?
---@param text string?
---@return string[]
function M.disp(buf, text)
  local l = merge.lines(text)
  if buf and is_dos(buf) then
    return merge.strip_cr(l)
  end
  return l
end

---Display-space lines → disk text for a buffer.
---@param buf integer?
---@param lines string[]
---@return string
function M.undisp(buf, lines)
  if buf and is_dos(buf) then
    return merge.join(merge.add_cr(lines))
  end
  return merge.join(lines)
end

---@param v string|false|nil
---@return string?
function M.opt(v)
  if v == false then
    return nil
  end
  return v
end

return M
