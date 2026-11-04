# agentdiff

Review file changes made by AI agents running outside Neovim, the way VS Code's
agent mode does. An agent (Claude Code, Copilot CLI, Codex, …) runs in another
tmux pane and writes straight to disk. agentdiff shows every one of those
changes inline as a pending diff, which you can step through and **keep** or
**undo** per change, per file or all at once. Edits you make in Neovim are
never part of the review.

By default only the edits agents report through their hooks are reviewed
(Claude Code and Copilot CLI; run `:Agentdiff hooks install` once), so code
generators, build scripts and file explorers writing into your projects never
show up as agent changes. For agents without hooks, or to also review the
agent's shell edits, the **writer** mode needs no setup at all: any change on
disk that Neovim did not make is the agent's (see [Attribution](#attribution)).

## Documentation

- [docs/](docs/README.md): how it works, with diagrams: [architecture](docs/architecture.md), [attribution](docs/attribution.md), [detection](docs/detection.md), [merge3](docs/merge3.md), [review UI](docs/review-ui.md), [testing](docs/testing.md), [design decisions](docs/decisions.md)
- [`:help agentdiff`](doc/agentdiff.txt): the full reference

## Requirements

- Neovim 0.12 or newer
- `git` on `PATH`. It's used only as a content store in a private directory;
  your project doesn't have to be a git repository, and if it is, agentdiff
  never writes to its `.git`.

No other plugins.

## Installation

With Neovim's built-in package manager (`:h vim.pack`):

```lua
vim.pack.add({ "https://github.com/RayIci/agentdiff.nvim" })
require("agentdiff").setup({})
```

Update it with `:lua vim.pack.update()`.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "RayIci/agentdiff.nvim",
  lazy = false, -- it has to see every write from startup on
  opts = {},
}
```

Don't lazy-load it on a command or key: it tells your edits from the agent's
by watching Neovim's own writes, so in the writer mode files you save before
it loads would later show up as agent changes. Help is in `:help agentdiff`.

## Setup

```lua
require("agentdiff").setup({
  -- attribution = "writer",  -- review every change Neovim didn't make (no hooks needed)
  -- No keymaps are created unless you pass them.
  keymaps = {
    next = "]a",
    prev = "[a",
    keep = "<leader>rk",
    undo = "<leader>ru",
  },
})
```

Then install the agent hooks once (see [Attribution](#attribution)):

```vim
:Agentdiff hooks install
```

Until a hook is installed, the hooks mode reviews nothing; agentdiff says so
once when it starts.

### Options

| Option | Default | Meaning |
|---|---|---|
| `attribution` | `"hooks"` | who changed a file: `"hooks"` (only what an agent hook reported) or `"writer"` (anything Neovim didn't write is the agent's); see [Attribution](#attribution) |
| `keymaps` | `false` | table of `action = lhs` (`next`, `prev`, `next_file`, `prev_file`, `keep`, `undo`, `keep_file`, `undo_file`, `keep_all`, `undo_all`, `panel`, `panel_tree`, `panel_list`, `view`, `overlay`, `resolve`); `keep`/`undo` are also mapped in visual mode |
| `panel` | see [Panel](#panel) | `view` (`"tree"` or `"list"`), `position` (`"right"`, `"left"`, `"top"`, `"bottom"`), `size` (`40` columns/rows, or `"30%"` / `0.3` of the editor), `icons` (`true`) |
| `poll_interval` | `1000` | ms between disk checks while Neovim is focused (`0` disables the timer) |
| `settle` | `300` | ms an unclaimed change waits before it's confirmed as the agent's |
| `claim_ttl` | `10000` | ms an unused claim stays valid |
| `max_file_size` | `1 MiB` | larger files are reviewed as whole files |
| `max_files` | `20000` | larger projects are not reviewed (with a notice) |
| `excludes` | build/cache dirs | gitignore-style patterns never reviewed, on top of `.gitignore` |
| `root` | git toplevel or cwd | force the project root; the home directory and `/` are never used unless forced |
| `confirm` | `true` | ask before keep-all / undo-all |
| `keep_on_stage` | `true` | staging a pending change in git keeps it (like VS Code); commits keep what they stage |
| `hint` | `true` | show the hint on the change nearest the cursor |
| `auto_start` | `true` | start on setup (on `VimEnter`) |

## Lua API

Every action is a function on `require("agentdiff")`:

| Function | What it does |
|---|---|
| `setup(opts)` | configure; starts reviewing unless `auto_start = false` |
| `start()` / `stop()` | start or stop reviewing the current project (this session only) |
| `enable()` / `disable()` / `toggle()` | turn review on / off, persisted across restarts; turning it back on starts each project clean from its current files |
| `enabled()` | true when review is on |
| `next()` / `prev()` | next / previous pending change, crossing into other files; wraps with a notice |
| `next_file()` / `prev_file()` | next / previous changed file |
| `open(path)` | open a pending file at its first change |
| `keep(opts)` | keep pending changes into the baseline; the file isn't touched |
| `undo(opts)` | restore the baseline of pending changes, on disk |
| `keep_file()` / `undo_file()` | keep / undo every change in the current file |
| `keep_all(opts)` / `undo_all(opts)` | every change in every file; asks first unless `{ force = true }` |
| `resolve(choice)` | resolve a conflicted file: `"accept"` (the agent's changes, your other unsaved edits on top), `"agent"`, `"mine"` or `"compare"` (asks when nil). Keep and undo on a conflicted file do `"accept"` and `"mine"` |
| `panel(opts)` | toggle the changed-files panel; `{ view = "tree" }` or `"list"` opens that view, closes it when it's showing, and switches from the other view |
| `toggle_view()` | toggle inline overlay ↔ side-by-side diff for the current file |
| `toggle_overlay()` | hide / show the overlay; nothing is kept or undone |
| `claim(paths)` | the next disk changes to these paths are yours (for tools that write files) |
| `reset(opts)` | forget every pending change of the current project and start over from its current files; asks first unless `{ force = true }` |
| `status()` | statusline summary, e.g. `3 files · 7 changes`; `""` when nothing is pending |
| `files()` | pending files in navigation order |
| `path_status(path)` | `"file"` (has pending changes), `"dir"` (contains such a file) or `nil`: cheap enough for every line of a file tree |
| `hooks_install(harness, scope)` / `hooks_uninstall(harness, scope)` | add / remove agentdiff's hook in an agent CLI: `harness` `"claude"`, `"copilot"` or `"all"` (default), `scope` `"user"` (default) or `"project"` (see [Attribution](#attribution)) |
| `hooks_status(opts)` | per harness: where the hook is installed and when it last reported an edit for this project; shown unless `{ silent = true }` |

`keep(opts)` and `undo(opts)` take:

| Option | Meaning |
|---|---|
| `scope` | `"hunk"` (default): the change under the cursor · `"file"` · `"all"` |
| `range` | `{ first, last }` lines (with `scope = "hunk"`): only the lines of pending changes in that range. Removed lines count as selected when the range starts at or above the change. |
| `path` | project-relative file (default: the current buffer) |
| `force` | with `scope = "all"`, skip the confirmation |

Undo goes through the file's buffer, loading it hidden when needed, so `u`
afterwards brings the agent's change back as pending. When the buffer has
unsaved edits of yours, the undone region is left unsaved with them and
reaches disk on your next `:w`. Undoing a file the agent created deletes it;
undoing a deletion restores the file.

## Command

`:[range]Agentdiff [subcommand]` (default: `panel`), with completion:

| Subcommand | Action |
|---|---|
| `next` / `prev` | next / previous change |
| `next_file` / `prev_file` | next / previous changed file |
| `keep` / `undo` | the change under the cursor; with a range, only those lines |
| `keep_file` / `undo_file` | every change in the current file |
| `keep_all` / `undo_all` | every change in every file (asks first) |
| `panel` | `panel [tree\|list]`: toggle the changed-files panel, in a view |
| `view` | toggle inline ↔ side-by-side |
| `overlay` | hide / show the overlay |
| `resolve` | resolve a conflicted file |
| `refresh` | check the disk now |
| `toggle` / `enable` / `disable` | turn review on / off (persisted) |
| `reset` | forget the current project's pending changes and start over from its files (asks first) |
| `status` | show the pending summary |
| `hooks` | `hooks install\|uninstall\|status [claude\|copilot\|all] [user\|project]`: manage agentdiff's hook in agent CLIs (default: `status`) |

## Panel

The changed-files panel shows every pending file as a **tree** (folders first,
a folder holding only one folder compacted as `lua/agentdiff`, each folder
with its total counts) or a **list** (file name, then its folder), with
right-aligned `+added −removed` counts and the status letter (`M` modified,
`A` created, `D` deleted, `B` binary, `C` conflicted).

```
 󰚩 Agent changes         5 files  +5 −2

  docs                            −1
     gone.md                    −1  D
  lua/agentdiff                +4 −1
    ui                         +2 −1
       icons.lua                +2  A
       panel.lua                −1  M
     init.lua                   +2  M
   README.md                    +1  M

 ? keys
```

| Key | Action |
|---|---|
| `<CR>` / `o` | open the file at its first change; on a folder, fold / unfold it |
| `K` / `U` | keep / undo the file |
| `gK` / `gU` | keep / undo everything |
| `t` | switch tree ↔ list |
| `R` | check the disk now |
| `?` | show every key |
| `q` | close |

```lua
require("agentdiff").setup({
  panel = {
    view = "tree",       -- or "list": the view panel() opens first
    position = "right",  -- "left", "top", "bottom"
    size = 40,           -- columns (or rows at top/bottom); "30%" or 0.3 for a share of the editor
    icons = true,        -- mini.icons or nvim-web-devicons when installed, built-in Nerd Font glyphs otherwise
  },
  keymaps = { panel_tree = "<leader>rp", panel_list = "<leader>rP" },
})
```

`panel_tree` and `panel_list` toggle their view and switch from the other one:
with the tree open, `panel_list` shows the list; pressing it again closes the
panel. `panel` toggles the last view used.

The panel window only ever shows the panel (`winfixbuf`). Files opened from it,
and the navigation actions run from it, open in an editing window: the window
you came from, another file window, or a new split beside the panel.

## Integrations

Optional modules, never loaded unless you require them:

```lua
-- neo-tree: review marks on changed files and folders
local nt = require("agentdiff.integrations.neotree")
require("neo-tree").setup({
  filesystem = { components = { agentdiff = nt.component }, renderers = nt.renderers() },
})
nt.setup()

-- oil: renames/moves/deletes in oil are yours, not the agent's
require("agentdiff.integrations.oil").setup()

-- grug-far: project-wide replaces are yours
require("grug-far").setup({
  hooks = { on_before_edit_file = require("agentdiff.integrations.grug_far").on_before_edit_file },
})
```

Writing your own: see [docs/extending.md](docs/extending.md).

## Events and statusline

- `User AgentdiffChanged` fires whenever the set of pending changes changes
  (detected, kept, undone, resolved).
- `require("agentdiff").status()` is a statusline component: it returns
  `3 files · 7 changes`, or `""` when nothing is pending. With lualine:

  ```lua
  sections = { lualine_x = { require("agentdiff").status } }
  ```

## Highlights

| Group | Default link | Used for |
|---|---|---|
| `AgentdiffAdd` | `DiffAdd` | lines the agent added or changed |
| `AgentdiffDelete` | `DiffDelete` | removed lines (virtual) |
| `AgentdiffHint` | `Comment` | the hint on the nearest change |
| `AgentdiffConflict` | `DiagnosticWarn` | changes overlapping your unsaved edits |
| `AgentdiffTreeFile` | `DiagnosticWarn` | file-tree mark of a file with pending changes |
| `AgentdiffTreeDir` | `DiagnosticWarn` | file-tree mark of a directory containing one |
| `AgentdiffPanelTitle` | `Title` | the panel title |
| `AgentdiffPanelCount` | `Comment` | totals in the title, folder counts, "whole file" |
| `AgentdiffPanelDir` / `AgentdiffPanelDirIcon` | `Directory` | folder names and icons |
| `AgentdiffPanelFileIcon` | `Normal` | built-in file icon (icon plugins bring their own groups) |
| `AgentdiffPanelFold` | `Comment` | fold markers |
| `AgentdiffPanelPath` | `Comment` | the folder of a file in the list view |
| `AgentdiffPanelAdded` / `AgentdiffPanelRemoved` | `Added` / `Removed` | `+n` / `−n` counts |
| `AgentdiffPanelModified` / `Created` / `Deleted` | `Changed` / `Added` / `Removed` | status letters `M` / `A` / `D` |
| `AgentdiffPanelConflicted` / `AgentdiffPanelBinary` | `DiagnosticError` / `Special` | status letters `C` / `B` |
| `AgentdiffPanelDeletedName` | strikethrough | the name of a deleted file |
| `AgentdiffPanelHelp` / `AgentdiffPanelKey` | `Comment` / `Special` | the key help |

## How it decides who changed what

Every file has a **baseline**: the last version you agreed with. Pending
changes are always *baseline → current content*.

These are the rules of the **writer** mode (`attribution = "writer"`). The
default [hooks mode](#attribution) replaces the first rule and the git rules
with "an agent hook reported the file"; the others apply to both.

- A change on disk that Neovim did not make is the **agent's**: the baseline
  stays, so the change becomes pending.
- Anything Neovim does is **yours**: typing, `:w`, format-on-save, LSP edits,
  shell commands run with `:!`, and tools that call `claim()`. Your edits are
  merged into the baseline too, so they never show up as pending. An edit
  inside a pending change becomes part of that change.
- When git moves HEAD (checkout, pull, reset, stash, commit), files git put
  back to HEAD's content are folded into the baseline instead of flagged.
- A change that only moves a file back toward its committed content (a
  discard: `git restore`, `git checkout -- f`, lazygit's file or hunk
  discard) is yours too. An agent edit moves away from HEAD, so it stays
  pending until you keep it.
- **Staging keeps** (as in VS Code): when you stage a pending change, in
  lazygit, `git add`, or `git commit -a`, it is kept, file or single hunk.
  The same check runs when review starts, so changes committed while Neovim
  was closed are kept too, deletions included. Unstaging never makes
  anything pending again. Turn it off with
  `keep_on_stage = false`.
- Files inside `.git` (commit messages, rebase todos) and ignored files are
  never reviewed, whoever writes them.

## Attribution

`attribution` chooses how a change on disk gets its author, for every project:

| Mode | A change Neovim didn't make is the agent's when… | Setup |
|---|---|---|
| `"hooks"` (default) | an agent hook reported that file around the time it changed | `:Agentdiff hooks install` once |
| `"writer"` | always (unless git produced it or it's a discard, above) | none; works with any agent, shell edits included |

In the hooks mode, everything else that writes into the project (generators,
build output, files created in a terminal or by a file explorer) is folded into
the baseline silently. Neovim's own writes, claims, staging-keeps and conflicts
work exactly as in the writer mode.

```vim
:Agentdiff hooks install            " Claude Code and Copilot CLI, user scope
:Agentdiff hooks install claude project
:Agentdiff hooks status             " where it's installed, last report for this project
:Agentdiff hooks uninstall
```

| Harness | user scope | project scope | Tools reported |
|---|---|---|---|
| `claude` (Claude Code) | `~/.claude/settings.json` | `.claude/settings.local.json` | `Edit`, `Write`, `MultiEdit`, `NotebookEdit` |
| `copilot` (Copilot CLI) | `~/.copilot/hooks/agentdiff.json` | `.github/hooks/agentdiff.json` | `edit`, `create`, `str_replace_editor`, `write`, `apply_patch` |

- **Install merges.** Your other settings and hooks are kept, the original
  file is backed up once to `<file>.agentdiff.bak`, and installing twice
  changes nothing. Uninstall removes only agentdiff's entries (Copilot's hook
  file is agentdiff's own and is deleted).
- **The hook** runs `bin/agentdiff-hook.lua` with this Neovim
  (`nvim --headless -u NONE -i NONE -l …`, about 40 ms, no other dependency).
  It records the edited files in the project's store, prints nothing and
  always exits 0, so it can never block or fail the agent's tool call.
  Neovim doesn't need to be running: edits made while it's closed are
  reviewed when you open the project.
- **The store location is baked into the hook command**, so the agent and
  Neovim always agree on it even if they see a different `XDG_STATE_HOME`.
  Run `:Agentdiff hooks install` again after changing `state_dir` or moving
  the plugin.
- **The agent can run anywhere** that sees the same files and the same
  Neovim path: another tmux pane, another terminal, in the background.
- **Shell edits aren't reviewed.** A file the agent changes by running a
  command (`sed -i`, a script) isn't reported by its file tools, so in the
  hooks mode it isn't reviewed, as in VS Code. Use the writer mode if you
  want those too.
- If `:Agentdiff hooks status` shows the hook installed but never a report
  after the agent edited a file, the CLI's payload isn't understood: please
  open an issue with the CLI's version.

## The store

Baselines live outside your project, one directory per project root:

```
stdpath("state")/agentdiff/<hash of the project root>/
  git/            private git directory (objects only, nothing is ever committed)
  baseline.idx    the baseline of every file
  observed.idx    the last disk content agentdiff has processed
  claims/         claims shared by every Neovim instance on the project
  lock/           cross-instance lock while the indexes are updated
  root            the project root, for humans
```

Every Neovim instance on the same project shares it, and it survives restarts,
so pending changes are still there after `:restart` or a crash. git runs with
a sanitized environment (no inherited `GIT_*`, no system or global config) and
never touches your project's `.git`. Paths ignored by your `.gitignore` files
and by the `excludes` option are never reviewed.

The on/off state lives in `stdpath("state")/agentdiff/enabled`, shared by all
projects.

**Resetting is always safe:** `:Agentdiff reset` does it for the current
project. By hand: delete the store directory (or a project's
subdirectory) and agentdiff rebuilds it from the files currently on disk,
with nothing pending.

## Tests

The suite runs headless, with no test framework:

```sh
nvim --headless -u NONE -l tests/run.lua            # everything
nvim --headless -u NONE -l tests/run.lua merge      # files whose name contains "merge"
```

Each test gets a temp project directory and a temp `XDG_STATE_HOME`; the
command exits non-zero when a test fails.
