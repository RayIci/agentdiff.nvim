# Spec Delta

## MODIFIED Requirements

### Requirement: Changed-files panel
The plugin SHALL provide a toggleable panel of every file with pending changes, with its status (modified, created, deleted, conflicted, binary) and added/removed line counts, shown either as a tree of folders and files or as a list of files, with colours and file icons. From the panel the user SHALL be able to open a file at its first change with `<CR>` or `o`, and keep or undo a file or all files.

#### Scenario: Panel lists counts
- **WHEN** an agent modified `a.lua` (+3 −1) and created `b.lua` (+20) and the user opens the panel
- **THEN** both files are shown with those statuses and counts

#### Scenario: Open from the panel
- **WHEN** the user selects `a.lua` in the panel
- **THEN** `a.lua` opens with the cursor on its first pending change

#### Scenario: Tree view
- **WHEN** the agent changed `lua/agentdiff/a.lua`, `lua/agentdiff/ui/b.lua` and `README.md` and the user opens the panel in the tree view
- **THEN** the folders are shown above their files, `lua/agentdiff` as one compacted folder, each folder can be collapsed and expanded, and each file shows its counts and status

#### Scenario: List view
- **WHEN** the user opens the panel in the list view
- **THEN** each changed file is one line with its name, its folder, its counts and its status

#### Scenario: Colours and icons
- **WHEN** the panel is shown
- **THEN** status letters, counts, folders and the title use the `AgentdiffPanel*` highlight groups, and files and folders have icons unless icons are turned off

## ADDED Requirements

### Requirement: Panel views and toggling
`panel()` SHALL toggle the panel in the last view used (initially the `panel.view` option, default tree). `panel({ view })` SHALL open the panel in that view when it is closed, close it when it shows that view, and switch to that view when it shows the other one. The keymap actions `panel_tree` and `panel_list` and `:Agentdiff panel tree|list` SHALL do the same, and `t` in the panel SHALL switch views.

#### Scenario: Toggle a view
- **WHEN** the panel is closed, the user opens it in the tree view, then asks for the tree view again
- **THEN** the panel opens as a tree, then closes

#### Scenario: Switch views
- **WHEN** the panel shows the tree and the user asks for the list view
- **THEN** the panel stays open and shows the list

### Requirement: Panel window
The panel SHALL open at the side given by `panel.position` (`right` by default, or `left`, `top`, `bottom`) with the size given by `panel.size`: a fixed number of columns or rows, or a share of the editor such as `"30%"` that follows the editor's size. The panel window SHALL show only the panel buffer, and files opened from the panel or by navigation SHALL open in an editing window, never in the panel window.

#### Scenario: Position and size
- **WHEN** the host sets `panel = { position = "left", size = "25%" }` and the user opens the panel
- **THEN** it opens at the left edge, a quarter of the editor wide

#### Scenario: Files never open in the panel
- **WHEN** the panel is the current window and the user opens a file from it, runs a navigation action, or `:edit`s another file
- **THEN** the file opens in an editing window (a new split when there is none) and the panel window keeps showing the panel, or the `:edit` fails
