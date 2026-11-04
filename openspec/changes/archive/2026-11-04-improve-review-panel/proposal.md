# Proposal

## Why

The changed-files panel is a plain list of `M path  +3 −1` lines in a fixed 40-column split on the left, with no colours. Opening a file from it sometimes replaces the panel itself: `wincmd p` can land back in the panel, and the global navigation keys (`next`, `prev`, …) edit in whatever window is current, the panel included. It should look and behave like the changes view of VS Code: a tree of folders and files with icons and coloured status, that stays where it is.

## What Changes

- The panel has two views: a **tree** (folders, compacted when they hold a single folder, collapsible) and a **list** (one line per file: name, then its folder). `t` switches between them; the `panel.view` option chooses the default (`"tree"`).
- Colours: status letters, added/removed counts, folders, the title and the key help use highlight groups (`AgentdiffPanel*`, linked to standard groups, overridable). Counts and status letters are right-aligned.
- Icons: file and folder icons from mini.icons or nvim-web-devicons when either is installed, built-in Nerd Font glyphs otherwise; `panel.icons = false` turns them off.
- Position and size: `panel.position` (`"right"` default, `"left"`, `"top"`, `"bottom"`) and `panel.size` (fixed columns/rows like `40`, or a share of the editor like `"30%"` or `0.3`, kept on resize).
- The panel window holds only the panel buffer (`winfixbuf`). Opening a file (`<CR>` or `o`) and the navigation actions always use a normal editing window: the previous one, else another file window, else a new split beside the panel.
- `<CR>`/`o` on a folder collapses or expands it. `?` shows the key help.
- `panel(opts)` takes `{ view = "tree"|"list" }`: the view that is showing closes the panel, the other view switches to it. New keymap actions `panel_tree` and `panel_list`, and `:Agentdiff panel [tree|list]`.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `agent-change-review`: the changed-files panel gains tree and list views, colours and icons, position and size options, view-specific toggling, and a window that only the panel occupies.

## Impact

- Code: `ui/panel.lua` (rewritten: model, render, window), new `ui/windows.lua` (picking the editing window), `ui/icons.lua`, `ui/highlights.lua` (panel groups), `actions/navigate.lua` (never edits in a non-editing window), `config.lua` (`panel` options, `panel_tree`/`panel_list` keymaps), `keymaps.lua`, `command.lua`, `init.lua` (`panel(opts)`).
- Public surface: a `panel` option table, two keymap actions, an optional argument to `panel()` and `:Agentdiff panel`. `panel()` without arguments toggles as before.
- Tests: the panel tests change (line format); new tests for the tree, list, icons, highlights, window placement and ownership, and the options.
- Optional use of mini.icons / nvim-web-devicons when present; no new dependency.
