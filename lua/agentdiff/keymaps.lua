---Optional keymaps: created only for the actions the host names in
---`opts.keymaps`. `keep` and `undo` are also mapped in visual mode, where they
---act on the selected lines.
---@class AgentdiffKeymapsModule
local M = {}

---@return integer[]
local function visual_range()
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  return { math.min(a, b), math.max(a, b) }
end

---@param keys AgentdiffKeymaps
---@param api Agentdiff
function M.create(keys, api)
  local normal_actions = {
    next = { api.next, "Next agent change" },
    prev = { api.prev, "Previous agent change" },
    next_file = { api.next_file, "Next changed file" },
    prev_file = { api.prev_file, "Previous changed file" },
    keep = {
      function()
        api.keep()
      end,
      "Keep change",
    },
    undo = {
      function()
        api.undo()
      end,
      "Undo change",
    },
    keep_file = { api.keep_file, "Keep file" },
    undo_file = { api.undo_file, "Undo file" },
    keep_all = {
      function()
        api.keep_all()
      end,
      "Keep all",
    },
    undo_all = {
      function()
        api.undo_all()
      end,
      "Undo all",
    },
    panel = {
      function()
        api.panel()
      end,
      "Changed files panel",
    },
    panel_tree = {
      function()
        api.panel({ view = "tree" })
      end,
      "Changed files (tree)",
    },
    panel_list = {
      function()
        api.panel({ view = "list" })
      end,
      "Changed files (list)",
    },
    view = { api.toggle_view, "Toggle side-by-side" },
    overlay = { api.toggle_overlay, "Hide/show overlay" },
    resolve = {
      function()
        api.resolve()
      end,
      "Resolve conflict",
    },
  }

  for name, lhs in pairs(keys) do
    local a = normal_actions[name]
    if a then
      vim.keymap.set("n", lhs, a[1], { desc = a[2] })
    end
  end
  if keys.keep then
    vim.keymap.set("x", keys.keep, function()
      api.keep({ range = visual_range() })
    end, { desc = "Keep selected lines" })
  end
  if keys.undo then
    vim.keymap.set("x", keys.undo, function()
      api.undo({ range = visual_range() })
    end, { desc = "Undo selected lines" })
  end
end

return M
