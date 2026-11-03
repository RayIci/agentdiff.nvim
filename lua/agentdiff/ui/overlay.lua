---Inline overlay: removed lines as virtual lines, added lines highlighted. The
---buffer text is never changed. Redraws whenever the review state is refreshed.
---@class AgentdiffOverlay
local M = {}

local hint = require("agentdiff.ui.hint")
local session = require("agentdiff.core.session")

M.ns = vim.api.nvim_create_namespace("agentdiff")

---@param text string
---@param ts integer
---@return string
local function expand_tabs(text, ts)
  if not text:find("\t", 1, true) then
    return text
  end
  local out, col = {}, 0
  for ch in text:gmatch(".") do
    if ch == "\t" then
      local n = ts - (col % ts)
      out[#out + 1] = (" "):rep(n)
      col = col + n
    else
      out[#out + 1] = ch
      col = col + 1
    end
  end
  return table.concat(out)
end

---Lines of a hunk's old side worth drawing (the trailing "" that only stands
---for a final newline is not a line).
---@param f AgentdiffFile
---@param h AgentdiffHunk
---@return string[]
local function removed_lines(f, h)
  local out = {}
  for i = h.a_lo + 1, h.a_hi do
    if not (i == #f.base and f.base[i] == "") then
      out[#out + 1] = f.base[i]
    end
  end
  return out
end

---Draw one buffer's overlay.
---@param s AgentdiffSession
---@param buf integer
function M.buffer(s, buf)
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local rel = session.rel_of_buf(s, buf)
  local f = rel and s.files[rel]
  if not f or s.overlay_hidden or s.views[buf] then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  if f.status == "deleted" and f.buf == nil then
    -- A leftover buffer of a file the agent deleted: show it all as removed.
    for row = 0, count - 1 do
      vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, { line_hl_group = "AgentdiffDelete", priority = 120 })
    end
    return
  end
  if f.whole or f.buf ~= buf then
    return
  end
  local ts = vim.bo[buf].tabstop
  local width = math.max(vim.o.columns, 80)
  local conflicted = f.status == "conflicted"
  for _, h in ipairs(f.hunks) do
    for row = h.b_lo, math.min(h.b_hi, count) - 1 do
      vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
        line_hl_group = conflicted and "AgentdiffConflict" or "AgentdiffAdd",
        priority = 120,
      })
    end
    local old = removed_lines(f, h)
    if #old > 0 then
      local virt = {}
      for _, l in ipairs(old) do
        local text = expand_tabs(l, ts)
        local pad = width - vim.fn.strdisplaywidth(text)
        virt[#virt + 1] = { { text .. (" "):rep(math.max(pad, 0)), "AgentdiffDelete" } }
      end
      local above = h.b_lo < count
      vim.api.nvim_buf_set_extmark(buf, M.ns, above and h.b_lo or (count - 1), 0, {
        virt_lines = virt,
        virt_lines_above = above,
        priority = 120,
      })
    end
  end
end

---Redraw every loaded project buffer and the hint.
---@param s AgentdiffSession
function M.all(s)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      M.buffer(s, b)
    end
  end
  hint.draw(s)
end

require("agentdiff.core.events").on("refreshed", function(s)
  M.all(s)
end)

return M
