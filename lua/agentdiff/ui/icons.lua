---Icons for the panel: mini.icons or nvim-web-devicons when available,
---built-in Nerd Font glyphs otherwise, nothing when icons are off.
---@class AgentdiffIcons
local M = {}

M.glyphs = {
  file = "󰈔",
  dir_closed = "\239\129\187", -- U+F07B nf-fa-folder
  dir_open = "\239\129\188", -- U+F07C nf-fa-folder_open
  fold_closed = "\239\129\148", -- U+F054 nf-fa-chevron_right
  fold_open = "\239\129\184", -- U+F078 nf-fa-chevron_down
  title = "󰚩",
}

---Fold markers when icons are off.
M.plain = { fold_closed = "▸", fold_open = "▾" }

---@param name string  file name
---@param enabled boolean
---@return string? icon
---@return string? hl
function M.file(name, enabled)
  if not enabled then
    return nil
  end
  local mini = rawget(_G, "MiniIcons")
  if type(mini) == "table" and type(mini.get) == "function" then
    local ok, icon, hl = pcall(mini.get, "file", name)
    if ok and icon then
      return icon, hl
    end
  end
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok and type(devicons) == "table" and devicons.get_icon then
    local icon, hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ":e"), { default = true })
    if icon then
      return icon, hl
    end
  end
  return M.glyphs.file, "AgentdiffPanelFileIcon"
end

---@param open boolean
---@param enabled boolean
---@return string fold   the fold marker
---@return string? icon  the folder icon (nil when icons are off)
function M.dir(open, enabled)
  if not enabled then
    return open and M.plain.fold_open or M.plain.fold_closed, nil
  end
  return open and M.glyphs.fold_open or M.glyphs.fold_closed,
    open and M.glyphs.dir_open or M.glyphs.dir_closed
end

return M
