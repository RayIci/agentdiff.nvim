---agentdiff: review file changes made by AI agents running outside Neovim.
---
---Entry point. Owns `setup()`, the `:Agentdiff` command, the optional keymaps
---and the public API. The plugin depends only on Neovim and the `git`
---executable and registers no keymaps unless the host passes `opts.keymaps`.
---@class Agentdiff
local M = {}

local claim_mod = require("agentdiff.actions.claim")
local hooks_mod = require("agentdiff.actions.hooks")
local command = require("agentdiff.command")
local keymaps = require("agentdiff.keymaps")
local navigate = require("agentdiff.actions.navigate")
local onoff = require("agentdiff.actions.onoff")
local reset_mod = require("agentdiff.actions.reset")
local resolve_mod = require("agentdiff.actions.resolve")
local review_actions = require("agentdiff.actions.review")
local buffers = require("agentdiff.editor.buffers")
local claims = require("agentdiff.core.claims")
local config = require("agentdiff.config")
local detect = require("agentdiff.detect.poller")
local git = require("agentdiff.detect.git")
local highlights = require("agentdiff.ui.highlights")
local hint = require("agentdiff.ui.hint")
local overlay = require("agentdiff.ui.overlay")
local state = require("agentdiff.core.state")
local session = require("agentdiff.core.session")
local store_mod = require("agentdiff.core.store")
local status = require("agentdiff.ui.status")
local util = require("agentdiff.core.util")

local global_group = vim.api.nvim_create_augroup("agentdiff_global", { clear = true })

---@type AgentdiffLifecycle
local lifecycle = {
  start = function()
    M.start()
  end,
  stop = function()
    M.stop()
  end,
}

---True when review is on (persisted across restarts).
M.enabled = onoff.enabled

---Start reviewing the project of the current directory (or `opts.root`).
function M.start()
  M.stop()
  local enabled, epoch = onoff.read()
  if not enabled then
    return
  end
  local opts = config.options
  local root = store_mod.resolve_root(opts)
  -- Never treat the home directory or / as a project unless asked to: that
  -- would snapshot everything under it.
  local home = vim.uv.fs_realpath(vim.env.HOME or "") or vim.env.HOME
  if not opts.root and (root == home or root == "/") then
    return
  end
  local ok, store = pcall(store_mod.open, root, opts)
  if not ok then
    util.notify(tostring(store), vim.log.levels.ERROR)
    return
  end
  store = onoff.fresh_store(store, root, opts, epoch)
  local s = session.new(root, store, opts)
  buffers.attach(s)
  hint.attach(s)
  detect.start(s)
  if s.ready then
    store:drop_unreviewable()
    vim.schedule(function()
      if session.get() == s then
        state.refresh(s)
        git.reconcile(s)
        detect.poll()
      end
    end)
  else
    store:snapshot(function(done, reason, count)
      if session.get() ~= s then
        return
      end
      if not done then
        if reason == "too_many" then
          util.notify(
            ("agentdiff: %s has %d files (max_files = %d); not reviewing it"):format(
              root,
              count,
              opts.max_files
            ),
            vim.log.levels.WARN
          )
          M.stop()
          store_mod.destroy(store)
        else
          util.notify("agentdiff: initial snapshot failed", vim.log.levels.ERROR)
        end
        return
      end
      s.ready = true
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local rel = vim.api.nvim_buf_is_loaded(b) and session.rel_of_buf(s, b)
        if rel then
          s.synced[b] = util.read_file(session.abs(s, rel)) or false
        end
      end
      state.refresh(s)
    end)
  end
end

---Stop reviewing (pending changes stay in the store).
function M.stop()
  local s = session.get()
  detect.stop()
  buffers.detach()
  if s then
    pcall(vim.api.nvim_del_augroup_by_id, s.group)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        vim.api.nvim_buf_clear_namespace(b, overlay.ns, 0, -1)
        vim.api.nvim_buf_clear_namespace(b, hint.ns, 0, -1)
      end
    end
    require("agentdiff.ui.panel").close()
  end
  session.current = nil
end

---Turn review on (persisted).
function M.enable()
  onoff.enable(lifecycle)
end

---Turn review off (persisted): nothing is detected or shown until enabled.
function M.disable()
  onoff.disable(lifecycle)
end

---Toggle review on/off (persisted).
function M.toggle()
  onoff.toggle(lifecycle)
end

---Forget every pending change of the current project and start over from
---its current files (other projects are untouched). Asks first unless
---`opts.force` or `confirm = false`.
---@param opts { force: boolean? }?
function M.reset(opts)
  reset_mod.reset(opts, lifecycle)
end

-- Navigation ------------------------------------------------------------------

M.next = navigate.next
M.prev = navigate.prev
M.next_file = navigate.next_file
M.prev_file = navigate.prev_file
M.open = navigate.open

-- Keep / undo -----------------------------------------------------------------

---Keep pending changes. `opts.scope`: "hunk" (default, the change under the
---cursor, or the lines of `opts.range`), "file" or "all".
M.keep = review_actions.keep

---Undo pending changes; same options as keep().
M.undo = review_actions.undo

function M.keep_file()
  review_actions.keep({ scope = "file" })
end

function M.undo_file()
  review_actions.undo({ scope = "file" })
end

---@param opts { force: boolean? }?
function M.keep_all(opts)
  review_actions.keep({ scope = "all", force = opts and opts.force })
end

---@param opts { force: boolean? }?
function M.undo_all(opts)
  review_actions.undo({ scope = "all", force = opts and opts.force })
end

---Resolve a conflicted file: "accept" (the agent's changes, your other unsaved
---edits on top), "agent", "mine" or "compare" (asks when nil).
M.resolve = resolve_mod.resolve

-- Views -----------------------------------------------------------------------

function M.panel()
  require("agentdiff.ui.panel").toggle()
end

function M.toggle_view()
  require("agentdiff.ui.sidebyside").toggle()
end

function M.toggle_overlay()
  local s = session.get()
  if not s then
    return
  end
  s.overlay_hidden = not s.overlay_hidden
  overlay.all(s)
end

-- Claims, status, events ------------------------------------------------------

---Mark the next disk changes of these paths (absolute or project-relative) as
---the user's. A path that is an existing directory claims every file under it.
M.claim = claim_mod.claim

---Statusline summary: "3 files · 7 changes", or "" when nothing is pending.
M.status = status.status

---Review status of a path for file trees: "file", "dir" or nil.
M.path_status = status.path_status

---Pending files in navigation order (read-only copies).
M.files = status.files

-- Agent hooks -----------------------------------------------------------------

---Install agentdiff's hook into an agent CLI: harness "claude", "copilot" or
---"all" (default), scope "user" (default) or "project".
---@param harness? string
---@param scope? "user"|"project"
---@return boolean ok
function M.hooks_install(harness, scope)
  return hooks_mod.install(harness, scope)
end

---Remove agentdiff's hook; same arguments as hooks_install().
---@param harness? string
---@param scope? "user"|"project"
---@return boolean ok
function M.hooks_uninstall(harness, scope)
  return hooks_mod.uninstall(harness, scope)
end

---Per harness: where agentdiff's hook is installed and when it last reported
---an edit for the current project. Shows it unless `opts.silent`.
---@param opts? { silent: boolean? }
---@return table<string, AgentdiffHookStatus>
function M.hooks_status(opts)
  return hooks_mod.status(opts)
end

-- Command ---------------------------------------------------------------------

---@type table<string, fun(range: integer[]?, args: string[])>
M.subcommands = command.subcommands(M)

require("agentdiff.ui.panel").set_handlers({
  status = function()
    return M.status()
  end,
  open = function(p)
    M.open(p)
  end,
  keep = function(o)
    M.keep(o)
  end,
  undo = function(o)
    M.undo(o)
  end,
  keep_all = function()
    M.keep_all()
  end,
  undo_all = function()
    M.undo_all()
  end,
  refresh = function()
    detect.now("poll")
  end,
})

-- Setup -----------------------------------------------------------------------

---@param opts AgentdiffOptions|table|nil
function M.setup(opts)
  local o = config.resolve(opts)
  local attribution = require("agentdiff.attribution")
  if not attribution.get(o.attribution) then
    error(
      ("agentdiff: unknown attribution '%s' (valid: %s)"):format(
        o.attribution,
        table.concat(attribution.names(), ", ")
      ),
      2
    )
  end
  highlights.define()
  vim.api.nvim_clear_autocmds({ group = global_group })
  vim.api.nvim_create_autocmd("ColorScheme", { group = global_group, callback = highlights.define })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = global_group,
    pattern = "global",
    callback = function()
      local s = session.get()
      if s and store_mod.resolve_root(config.options) ~= s.root then
        M.start()
      end
    end,
  })
  command.create(M.subcommands)
  if type(o.keymaps) == "table" then
    keymaps.create(o.keymaps, M)
  end
  if o.auto_start then
    if vim.v.vim_did_enter == 1 then
      M.start()
    else
      vim.api.nvim_create_autocmd("VimEnter", { group = global_group, once = true, callback = M.start })
    end
  end
end

-- Test hooks --------------------------------------------------------------------

M._test = {
  ---Stop everything and forget the session (between tests).
  reset = function()
    M.stop()
    vim.api.nvim_clear_autocmds({ group = global_group })
    pcall(vim.api.nvim_del_user_command, "Agentdiff")
  end,
  ---Block until the initial snapshot exists.
  wait_ready = function(ms)
    return vim.wait(ms or 5000, function()
      local s = session.get()
      return s ~= nil and s.ready and s.refreshed
    end, 10)
  end,
  ---Detect synchronously. settle = false confirms unclaimed changes at once.
  poll_now = function(opts)
    detect.now("poll", opts or { settle = false })
  end,
  ---Run debounced buffer updates now.
  flush = function()
    local s = session.get()
    if s then
      buffers.flush(s)
    end
  end,
  session = session.get,
}

return M
