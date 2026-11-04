---agentdiff configuration: defaults, validation and the resolved options.
---@class AgentdiffConfigModule
local M = {}

---Keys the plugin maps when the host passes them. Every field is optional; an
---absent field means "no mapping for this action".
---@class AgentdiffKeymaps
---@field next? string        next pending change, across files
---@field prev? string        previous pending change, across files
---@field next_file? string   next changed file
---@field prev_file? string   previous changed file
---@field keep? string        keep the change under the cursor (visual: the selected lines)
---@field undo? string        undo the change under the cursor (visual: the selected lines)
---@field keep_file? string   keep every change in the current file
---@field undo_file? string   undo every change in the current file
---@field keep_all? string    keep every change in every file
---@field undo_all? string    undo every change in every file
---@field panel? string       toggle the changed-files panel (last view used)
---@field panel_tree? string  toggle the panel as a tree (switches from the list)
---@field panel_list? string  toggle the panel as a list (switches from the tree)
---@field view? string        toggle inline / side-by-side for the current file
---@field overlay? string     hide / show the overlay
---@field resolve? string     resolve a conflicted file

---@class AgentdiffPanelOptions
---@field view "tree"|"list"                      the view the panel first opens in
---@field position "right"|"left"|"top"|"bottom"  the edge it opens at
---@field size integer|number|string|fun(ctx: { position: string, total: integer }): integer|number|string  columns/rows (40), a share of the editor (0.3, "30%"), or a function returning one
---@field icons boolean                           file and folder icons (mini.icons, nvim-web-devicons or built-in)

---@class AgentdiffOptions
---@field panel AgentdiffPanelOptions     the changed-files panel
---@field keymaps AgentdiffKeymaps|false  mappings to create; false (default) creates none
---@field attribution string               who changed a file: "hooks" (default: what agent hooks report) or "writer" (anything Neovim didn't write)
---@field poll_interval integer           ms between disk checks while Neovim is focused
---@field settle integer                  ms before an unclaimed change is confirmed as the agent's
---@field claim_ttl integer               ms a claim stays valid
---@field max_file_size integer           bytes above which a file is reviewed as a whole
---@field max_files integer               projects with more files are not reviewed (snapshot skipped)
---@field excludes string[]               gitignore-style patterns never reviewed
---@field state_dir? string               where per-project stores live (default: stdpath("state")/agentdiff)
---@field root? string                    force the project root (default: git toplevel or cwd)
---@field confirm boolean                 ask before keep-all / undo-all
---@field keep_on_stage boolean           staging a pending change in git keeps it (like VS Code)
---@field hint boolean                    show the hint on the change nearest the cursor
---@field auto_start boolean              start reviewing on setup (tests turn this off)

---@type AgentdiffOptions
M.defaults = {
  keymaps = false,
  attribution = "hooks",
  panel = { view = "tree", position = "right", size = 40, icons = true },
  poll_interval = 1000,
  settle = 300,
  claim_ttl = 10000,
  max_file_size = 1024 * 1024,
  max_files = 20000,
  excludes = {
    ".git/",
    "node_modules/",
    ".venv/",
    "venv/",
    "__pycache__/",
    ".mypy_cache/",
    ".pytest_cache/",
    ".ruff_cache/",
    ".next/",
    ".nuxt/",
    ".cache/",
    "dist/",
    "build/",
    "target/",
    "bin/",
    "obj/",
    "*.swp",
    "*.swo",
    ".DS_Store",
  },
  state_dir = nil,
  root = nil,
  confirm = true,
  keep_on_stage = true,
  hint = true,
  auto_start = true,
}

---@type AgentdiffOptions
M.options = vim.deepcopy(M.defaults)

local keymap_fields = {
  "next",
  "prev",
  "next_file",
  "prev_file",
  "keep",
  "undo",
  "keep_file",
  "undo_file",
  "keep_all",
  "undo_all",
  "panel",
  "panel_tree",
  "panel_list",
  "view",
  "overlay",
  "resolve",
}
M.keymap_fields = keymap_fields

---A panel size value: columns/rows (≥ 1), a fraction (0, 1) or "N%".
---@param size any
---@return boolean
function M.valid_size(size)
  if type(size) == "number" then
    return size > 0
  end
  local pct = type(size) == "string" and tonumber(size:match("^(%d+)%%$"))
  return pct ~= nil and pct > 0 and pct <= 100
end

---Merge user options over the defaults and validate them.
---@param opts table?
---@return AgentdiffOptions
function M.resolve(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  local o = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- excludes is a list: replace, don't merge index by index.
  if opts.excludes then
    o.excludes = vim.deepcopy(opts.excludes)
  end
  vim.validate("keymaps", o.keymaps, { "table", "boolean" })
  vim.validate("attribution", o.attribution, "string")
  vim.validate("poll_interval", o.poll_interval, "number")
  vim.validate("settle", o.settle, "number")
  vim.validate("claim_ttl", o.claim_ttl, "number")
  vim.validate("max_file_size", o.max_file_size, "number")
  vim.validate("max_files", o.max_files, "number")
  vim.validate("excludes", o.excludes, "table")
  vim.validate("state_dir", o.state_dir, "string", true)
  vim.validate("root", o.root, "string", true)
  vim.validate("confirm", o.confirm, "boolean")
  vim.validate("keep_on_stage", o.keep_on_stage, "boolean")
  vim.validate("hint", o.hint, "boolean")
  vim.validate("auto_start", o.auto_start, "boolean")
  vim.validate("panel", o.panel, "table")
  local p = o.panel
  if p.view ~= "tree" and p.view ~= "list" then
    error(('agentdiff: panel.view must be "tree" or "list", got %s'):format(vim.inspect(p.view)))
  end
  if not vim.tbl_contains({ "right", "left", "top", "bottom" }, p.position) then
    error(
      ("agentdiff: panel.position must be right, left, top or bottom, got %s"):format(vim.inspect(p.position))
    )
  end
  if type(p.size) ~= "function" and not M.valid_size(p.size) then
    error(
      ('agentdiff: panel.size must be a number of columns/rows, a fraction, "N%%" or a function, got %s'):format(
        vim.inspect(p.size)
      )
    )
  end
  vim.validate("panel.icons", p.icons, "boolean")
  if type(o.keymaps) == "table" then
    for k, v in pairs(o.keymaps) do
      if not vim.tbl_contains(keymap_fields, k) then
        error(("agentdiff: unknown keymap '%s'"):format(k))
      end
      vim.validate("keymaps." .. k, v, "string")
    end
  end
  M.options = o
  return o
end

---@return string
function M.state_dir()
  return M.options.state_dir or (vim.fn.stdpath("state") .. "/agentdiff")
end

return M
