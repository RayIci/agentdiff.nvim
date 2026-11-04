# Tasks

Each group ends with `make test`, `make fmt-check` and lua_ls clean, and is committed on its own.

## 1. Window ownership

- [x] 1.1 Add `ui/windows.lua` (editing window, new split beside the panel) and make `navigate`'s jump use it (D6); open the panel with `winfixbuf` (D5); verify "Files never open in the panel" (open from the panel, `next` from the panel, `:edit` in the panel, the panel as the only window)

## 2. Options, views and toggling

- [x] 2.1 Add the `panel` options (`view`, `position`, `size`, `icons`) with validation, position and size (D5); verify "Position and size" for every position, fixed and percentage sizes, resize, and invalid values
- [x] 2.2 Add `panel(opts)`, the `panel_tree`/`panel_list` keymap actions, `:Agentdiff panel tree|list` with completion and `t` (D7); verify "Toggle a view", "Switch views" and the public-surface test

## 3. Tree, list, colours and icons

- [x] 3.1 Rewrite the panel as rows then render (D1), with the tree (compacted, collapsible folders with counts) and the list (D2); verify "Panel lists counts", "Open from the panel", "Tree view", "List view", folder collapse, keep/undo from both views
- [x] 3.2 Add `ui/icons.lua` (D3) and the panel highlight groups (D4); verify "Colours and icons" with icons on and off and a fake icon provider, and the highlight-group test

## 4. Docs

- [x] 4.1 Document the panel views, keys, options, highlight groups and window behaviour in the README, `doc/agentdiff.txt` and `docs/review-ui.md`; verify the API doc tests, `:helptags` and Mermaid parsing

## Workflow follow-up

- Sync the `agent-change-review` delta and archive this change.
