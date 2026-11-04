# Design

## Context

`ui/panel.lua` builds plain lines from `s.order`/`s.files`, opens `topleft 40vsplit`, and opens files with `wincmd p` then `handlers.open(path)`; `actions/navigate.lua`'s `jump` runs `:edit` in the current window. `ui/` may require only `core/` and lower; `actions/` may require `ui/`.

## Goals / Non-Goals

**Goals:** tree and list views with icons and colours; configurable position and size; a panel window nothing else can take over; file opening that never lands in the panel.

**Non-Goals:** a floating panel; per-hunk rows in the panel (the overlay and navigation cover hunks); file operations (rename, delete) from the panel.

## Decisions

### D1. A row model, then rendering
`panel.rows(s, view)` turns the session's files into rows `{ kind = "dir"|"file", depth, text, path?, dir?, hl = {…}, right = {…} }`. Rendering writes the rows' text, then highlights them and adds right-aligned virtual text (`virt_text_pos = "right_align"`) with `+a −r` and the status letter. Tests read the rows and the buffer; the right-aligned part is virtual so it never shifts with the window width.

### D2. The tree
Paths split on `/` into nested folders, folders before files, both sorted by name. A folder holding only one folder and no files is shown compacted (`lua/agentdiff`), as VS Code does. Each folder shows the sum of its files' counts. Collapsed folders are remembered by path while Neovim runs. `<CR>`/`o` on a folder toggles it. The list view is one row per file in navigation order: the file name, then its folder in a dimmer group.

### D3. Icons
`ui/icons.lua`: when `panel.icons` is true, use `MiniIcons.get` if mini.icons is set up, else `nvim-web-devicons.get_icon` if it can be required, else built-in Nerd Font glyphs (file, open/closed folder, chevrons). With `icons = false`, folders get `▾`/`▸` and files no icon. Icon highlight groups come from the icon provider.

### D4. Highlight groups
Defined with `default = true`, linked to standard groups: `AgentdiffPanelTitle` → `Title`, `AgentdiffPanelCount` → `Comment`, `AgentdiffPanelDir` → `Directory`, `AgentdiffPanelPath` → `Comment` (the folder in list rows), `AgentdiffPanelAdded` → `Added`, `AgentdiffPanelRemoved` → `Removed`, `AgentdiffPanelModified` → `Changed`, `AgentdiffPanelCreated` → `Added`, `AgentdiffPanelDeleted` → `Removed`, `AgentdiffPanelConflicted` → `DiagnosticError`, `AgentdiffPanelBinary` → `Special`, `AgentdiffPanelHelp` → `Comment`, `AgentdiffPanelKey` → `Special`.

### D5. The window
Opened with `nvim_open_win(buf, true, { split = "right"|"left"|"above"|"below", win = -1 })`, a full-height (or full-width) split at the edge of the tab. Size: an integer ≥ 1 is columns (left/right) or rows (top/bottom); a number in (0, 1) or a `"N%"` string is a share of `columns` or of `lines - cmdheight`, recomputed on `VimResized`. Window options: `winfixbuf`, `winfixwidth`/`winfixheight`, no number/sign/fold columns, `cursorline`, no wrap. `winfixbuf` is what keeps other buffers out: `:edit`, `:buffer` and plugins that open files in the current window get an error instead of replacing the panel. A panel left open in another tab is closed and reopened in the current one.

### D6. Picking the editing window
`ui/windows.lua` `main_win()`: the previous window (`winnr("#")`) if it is an editing window, else the first editing window of the tab, else nil. An editing window is non-floating, without `winfixbuf`, showing a buffer with an empty `buftype`. When there is none, the panel opens a new split beside itself (on the side away from the edge) and uses it. `navigate`'s `jump` switches to `main_win()` (or that new split) before editing when the current window isn't an editing window, so `next`/`prev` from the panel work too.

### D7. Toggling by view
`panel({ view })`: closed → open in that view; open in that view → close; open in the other view → switch. `panel()` toggles with the last view used (default `panel.view`). `t` in the panel switches views. Keymap actions `panel_tree` and `panel_list` call `panel({ view = "tree" })` and `panel({ view = "list" })`.

## Risks / Trade-offs

- [Plugins that try to open a file in the current window error when it is the panel] → that is the requested behaviour; they work from any other window.
- [Nerd Font glyphs without a Nerd Font] → `panel.icons = false`.
- [`Added`/`Changed`/`Removed` don't exist in very old colourschemes] → they are Neovim defaults since 0.10; colourschemes may override the `AgentdiffPanel*` groups.
