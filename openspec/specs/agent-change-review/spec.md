# agent-change-review Specification

## Purpose
Reviews file changes made by AI agents running outside Neovim, the way VS Code's agent mode does: every change an agent writes to disk is shown inline as a pending diff that can be stepped through and kept or undone, while edits the user makes in Neovim never become part of the review.

## Requirements

### Requirement: Self-contained agentdiff plugin
Agent change review SHALL be provided by a self-contained `agentdiff` plugin module that depends only on Neovim and the `git` executable, not on other plugins or on the host configuration's modules, so it can be moved to its own repository without code changes. It SHALL expose a `setup(opts)` entry point and SHALL NOT register keymaps the host has not asked for.

#### Scenario: Relocatable module
- **WHEN** the plugin directory is moved to a standalone repository and loaded from there
- **THEN** it functions identically without edits to its own source

#### Scenario: No unrequested keymaps
- **WHEN** the host calls `setup()` without a keymaps option
- **THEN** the plugin defines no mappings, and every action is still available through its Lua API and command

### Requirement: Agent changes become pending reviews
In the writer attribution mode (`attribution = "writer"`), any change to a file in the project that Neovim did not make SHALL be treated as an agent change. A file's pending changes SHALL be exactly the difference between its baseline (the last agreed content) and its current content, and SHALL stay pending until kept or undone. Detection in this mode SHALL need no configuration of the agent.

#### Scenario: Agent edit from another tmux pane
- **WHEN** the writer mode is on and Claude Code running in another tmux pane edits `lua/foo.lua`
- **THEN** that edit appears in Neovim as a pending change of `lua/foo.lua`

#### Scenario: File never opened in Neovim
- **WHEN** an agent edits a project file that has no Neovim buffer
- **THEN** the file is listed with its pending changes and opening it shows them inline

#### Scenario: Any harness
- **WHEN** the same edit is made by Copilot CLI or Codex instead of Claude Code, with no hooks or settings added to either
- **THEN** it is shown as a pending change in the same way

### Requirement: Change detection timing
While Neovim is focused, an agent change SHALL be detected within 2 seconds of the write without user action. Changes made while Neovim is unfocused SHALL be detected no later than when Neovim regains focus, and changes made while Neovim was not running SHALL be detected at startup against the persisted baseline.

#### Scenario: Live update while watching
- **WHEN** Neovim is focused and an agent writes a file shown in a window
- **THEN** the window shows the change as pending within 2 seconds

#### Scenario: Agent worked while Neovim was closed
- **WHEN** an agent edits files while Neovim is not running and Neovim is then started in the project
- **THEN** those edits are shown as pending changes

### Requirement: User edits never become pending
Changes made through Neovim — typing in a buffer, writing it, format-on-save, LSP edits and any other buffer modification — SHALL be the user's. A user edit that does not touch a pending change SHALL be applied to the baseline as well, so it never appears as a pending change, whether or not the buffer has been written.

#### Scenario: Typing outside agent changes
- **WHEN** a file has a pending agent change at line 10 and the user edits line 40 and writes the file
- **THEN** only the change at line 10 is pending

#### Scenario: Format on save
- **WHEN** the user writes a buffer and a formatter rewrites lines that contain no pending change
- **THEN** no new pending change appears

### Requirement: Edits inside a pending change
A user edit that touches a pending agent change SHALL become part of that change's new content; the change SHALL stay pending, Keep SHALL accept the edited content, and Undo SHALL restore the baseline content, discarding the user's edit inside the change.

#### Scenario: Tweak then keep
- **WHEN** the user edits a line added by a pending agent change and then keeps that change
- **THEN** the edited line becomes part of the baseline and nothing is pending

#### Scenario: Tweak then undo
- **WHEN** the user edits a line added by a pending agent change and then undoes that change
- **THEN** the file returns to the baseline content in that region

### Requirement: Saving never accepts agent changes
Writing a buffer that contains pending agent changes SHALL NOT keep them; they SHALL remain pending after the write.

#### Scenario: Write with pending changes
- **WHEN** a buffer shows two pending agent changes and the user writes it with `:w`
- **THEN** both changes are still pending

### Requirement: Claimed changes
The plugin SHALL provide a `claim(paths)` API that marks the next disk changes to the given paths as the user's. File changes made by a shell command run from Neovim (`:!`, filter commands such as `:%!`) SHALL be claimed automatically.

#### Scenario: Shell command from Neovim
- **WHEN** the user runs `:!sed -i 's/a/b/' lua/foo.lua`
- **THEN** the resulting change is not shown as pending

#### Scenario: Tool claims its writes
- **WHEN** a file explorer renames `a.lua` to `b.lua` and calls `claim` for both paths
- **THEN** the rename is not shown as pending

### Requirement: Agent writes to a buffer with unsaved edits
When an agent writes a file whose buffer has unsaved user edits, and the agent's changes do not overlap the user's, the buffer SHALL receive the agent's changes as pending changes while the user's edits remain unsaved, non-pending edits. Neovim's own "file changed" prompt SHALL NOT appear.

#### Scenario: Non-overlapping edits merge
- **WHEN** the user has unsaved edits at line 5 and an agent writes a change at line 50 of the same file
- **THEN** the buffer contains both, the change at line 50 is pending, line 5 is still an unsaved edit, and no prompt appears

### Requirement: Overlapping agent and unsaved user edits
When an agent's changes overlap a buffer's unsaved user edits, the buffer SHALL be left unchanged and the file SHALL be marked conflicted. The user SHALL be able to take the agent's version (buffer reloaded from disk, all agent changes pending, discarded edits recoverable with undo), keep their own (the agent's changes to the file undone on disk, unsaved edits kept), or compare the two side by side.

#### Scenario: Conflict is flagged
- **WHEN** the user has an unsaved edit at line 5 and an agent rewrites line 5 of the same file
- **THEN** the buffer is unchanged and the file is shown as conflicted

#### Scenario: Keep mine
- **WHEN** the user resolves a conflicted file by keeping their own version
- **THEN** the file on disk returns to its baseline, the buffer keeps the user's unsaved edits, and the file has no pending changes

### Requirement: Baseline store isolation
Baselines SHALL be kept per project outside the project directory. The plugin SHALL NOT modify the project's own git repository state (refs, index, objects, config, hooks), and SHALL only read it to recognise git operations. Review SHALL work in directories that are not git repositories. Paths ignored by the project's `.gitignore` files or by the plugin's default excludes SHALL NOT be reviewed.

#### Scenario: Project git untouched
- **WHEN** agent changes are detected, kept and undone in a git repository
- **THEN** `git status`, the index and every ref of that repository are unchanged by the plugin

#### Scenario: Not a git repository
- **WHEN** Neovim is started in a directory without a git repository and an agent edits a file there
- **THEN** the edit is shown as a pending change

#### Scenario: Ignored paths
- **WHEN** an agent writes inside a directory listed in `.gitignore` (for example `node_modules/`)
- **THEN** nothing is shown as pending

### Requirement: Baseline persistence and sharing
Baselines and pending changes SHALL persist across Neovim restarts, including `:restart` and crashes. Every Neovim instance open on the same project SHALL share them, so a change written by any instance counts as the user's in all instances.

#### Scenario: Pending survives restart
- **WHEN** a file has pending agent changes and the user runs `:restart`
- **THEN** the same changes are pending after the restart

#### Scenario: Second instance
- **WHEN** two Neovim instances are open on the same project and the user writes a file in the first
- **THEN** the second instance does not show that write as a pending change

### Requirement: Non-blocking initial snapshot
The first baseline snapshot of a project SHALL be taken in the background without delaying Neovim's startup or blocking editing. Changes to a file before its baseline exists SHALL NOT be reported as pending.

#### Scenario: Large project startup
- **WHEN** Neovim starts in a large project with no existing baseline
- **THEN** the editor is usable immediately and review becomes active once the snapshot completes

### Requirement: Git metadata and ignored files are never reviewed
Files inside a `.git` directory and files ignored by the project's `.gitignore` files or the plugin's excludes SHALL NOT be reviewed, whoever writes them, including Neovim itself. Entries for such paths that an earlier version stored SHALL be dropped when review starts.

#### Scenario: Writing a commit message
- **WHEN** git opens `.git/COMMIT_EDITMSG` in Neovim and the user writes the message and saves
- **THEN** nothing is shown as pending, before or after git removes or rewrites the file

#### Scenario: Saving an ignored file
- **WHEN** the user saves a file under an ignored directory and an agent later rewrites it
- **THEN** neither change is shown as pending

### Requirement: Discarded changes are not agent changes
A change that only moves a tracked file back toward its committed (HEAD) content, in whole or in part, SHALL be treated as the user's (discarding through git or a git client), even when HEAD does not move. A change that moves a file away from HEAD SHALL still be the agent's.

#### Scenario: Discard in a git client
- **WHEN** an agent's edit to a tracked file is pending and the user discards the file's changes in lazygit (or runs `git restore` in another pane)
- **THEN** the file is no longer pending and nothing new is shown

#### Scenario: Discard one hunk
- **WHEN** an agent changed two regions of a tracked file and the user discards one of them in lazygit
- **THEN** only the other region is still pending

#### Scenario: Unstaged agent edit shown
- **WHEN** an agent edits a tracked file and nothing is staged
- **THEN** the edit is shown as pending

### Requirement: Persistent on/off toggle
The plugin SHALL provide enable, disable and toggle actions and subcommands. The state SHALL be global and persisted, so it survives restarts. While disabled nothing is detected or displayed. When review is enabled again, each project's baseline SHALL start from its current disk content, so nothing changed while disabled is shown as pending.

#### Scenario: Off survives restart
- **WHEN** the user disables review and restarts Neovim
- **THEN** review stays off until the user enables it

#### Scenario: Enabling starts clean
- **WHEN** the user disables review, edits and saves files, an agent edits files, and the user enables review again
- **THEN** nothing is shown as pending, and later agent changes are shown as usual

### Requirement: Project size guards
Review SHALL NOT start automatically when the project root would be the user's home directory or `/`, unless a root is configured explicitly. When a project has more reviewable files than a configurable limit (default 20 000), the plugin SHALL NOT snapshot it and SHALL tell the user why.

#### Scenario: Neovim opened in the home directory
- **WHEN** Neovim is started in the home directory, which is not a git repository
- **THEN** no store is created and nothing is reviewed

#### Scenario: Too many files
- **WHEN** Neovim is started in a project with more files than the limit
- **THEN** a notice names the project and the limit, and the project is not reviewed

### Requirement: Git operations are not agent changes
When the project's HEAD or index moves (checkout, switch, pull, merge, rebase, stash, reset, commit), files whose content git itself changed SHALL be folded into the baseline instead of becoming pending. Pending agent changes in files git did not change SHALL stay pending; a commit SHALL NOT undo them, and only what it stages is kept (see "Staging keeps changes").

#### Scenario: Branch switch
- **WHEN** the user runs `git switch other-branch` in another tmux pane
- **THEN** the files git changed are not shown as pending

#### Scenario: Commit of other files
- **WHEN** a file has pending agent changes and the user commits other files
- **THEN** that file's changes are still pending after the commit

### Requirement: Inline change overlay
In every window showing a file with pending changes, removed lines SHALL be shown as virtual lines in place and added lines SHALL be highlighted, without changing the buffer text. The overlay's highlight groups SHALL link to `DiffDelete` and `DiffAdd` by default so they work under any colorscheme.

#### Scenario: Modified line
- **WHEN** an agent replaces one line with another
- **THEN** the old line is shown as a removed virtual line directly above the new, highlighted line

#### Scenario: Buffer text untouched
- **WHEN** the overlay is shown
- **THEN** the buffer's lines are exactly the file's current content and removed lines cannot be edited or yanked as text

### Requirement: Change hint
The pending change under or nearest the cursor SHALL show a hint with its position among all pending changes of the session ("2/5") and, when mapped, the keys that keep or undo it.

#### Scenario: Hint position
- **WHEN** there are five pending changes in total and the cursor is on the second
- **THEN** that change's hint reads 2/5

### Requirement: Hide and show the overlay
The overlay SHALL be toggleable per session; hiding it SHALL NOT keep, undo or forget any pending change.

#### Scenario: Hide and restore
- **WHEN** the user hides the overlay and shows it again
- **THEN** the same changes are displayed as pending

### Requirement: Navigation between changes
The plugin SHALL provide next and previous change actions that move through pending changes in a stable order across files, opening the next changed file after the last change of the current one and wrapping around with a notice at the end. It SHALL also provide next and previous changed file actions.

#### Scenario: Cross into the next file
- **WHEN** the cursor is on the last pending change of `a.lua` and `b.lua` also has pending changes
- **THEN** next change opens `b.lua` at its first pending change

#### Scenario: Wrap around
- **WHEN** the cursor is on the last pending change of the last file and the user moves to the next change
- **THEN** the cursor moves to the first pending change of the first file and a notice reports the wrap

### Requirement: Keep changes
Keep SHALL accept pending changes into the baseline without altering the file, for the change under the cursor, for every change in the current file, or for every change in every file. Keeping all files SHALL ask for confirmation.

#### Scenario: Keep one change
- **WHEN** a file has two pending changes and the user keeps the one under the cursor
- **THEN** the file is unchanged on disk and only the other change is pending

#### Scenario: Keep all asks first
- **WHEN** the user keeps all changes
- **THEN** a confirmation is shown, and only on confirming are all pending changes accepted

### Requirement: Undo changes
Undo SHALL restore the baseline content of pending changes, for the change under the cursor, for every change in the current file, or for every change in every file, writing the result to disk; when the buffer has unsaved user edits, the result stays unsaved with them until the user writes it. Undoing all files SHALL ask for confirmation. An undo SHALL be reversible with Neovim's undo in the affected buffer.

#### Scenario: Undo one change
- **WHEN** the user undoes the change under the cursor
- **THEN** that region returns to its baseline content on disk and the change is no longer pending

#### Scenario: Undo with unsaved edits
- **WHEN** the buffer has an unsaved user edit elsewhere and the user undoes a pending change
- **THEN** the change is no longer pending, the user's edit is still unsaved, and nothing is written until the user writes the buffer

#### Scenario: Undo is undoable
- **WHEN** the user undoes a pending change and then presses `u` in that buffer
- **THEN** the agent's content is back and the change is pending again

### Requirement: Windows are never closed
Keeping or undoing a change that removes a file's buffer SHALL show another buffer (the alternate one, or an empty one) in every window that displayed it, and SHALL NOT close a window or exit Neovim.

#### Scenario: Undo the only buffer
- **WHEN** the only file buffer shows a file the agent created, beside a neo-tree window, and the user undoes that file
- **THEN** the file is deleted, both windows stay open showing an empty buffer and neo-tree, and Neovim keeps running

### Requirement: Created and deleted files
A file the agent created SHALL be reviewed as a change from nothing, and a file the agent deleted as a change to nothing. Undoing a created file SHALL delete it; undoing a deleted file SHALL restore it. A rename SHALL be reviewed as a deletion plus a creation.

#### Scenario: Undo a created file
- **WHEN** an agent creates `new.lua` and the user undoes that file
- **THEN** `new.lua` no longer exists and no buffer for it remains

#### Scenario: Undo a deleted file
- **WHEN** an agent deletes `old.lua` and the user undoes that file
- **THEN** `old.lua` exists again with its baseline content

### Requirement: Partial keep and undo
Keep and undo SHALL also accept a visual line range, applying only to the lines of pending changes inside that range and leaving the rest of those changes pending.

#### Scenario: Keep part of a change
- **WHEN** a pending change adds lines 10–14 and the user selects lines 10–11 and keeps the selection
- **THEN** lines 10–11 join the baseline and lines 12–14 remain pending

### Requirement: Changed-files panel
The plugin SHALL provide a toggleable panel listing every file with pending changes, with its status (modified, created, deleted, conflicted, binary) and added/removed line counts, ordered as navigation is. From the panel the user SHALL be able to open a file at its first change, and keep or undo a file or all files.

#### Scenario: Panel lists counts
- **WHEN** an agent modified `a.lua` (+3 −1) and created `b.lua` (+20) and the user opens the panel
- **THEN** both files are listed with those statuses and counts

#### Scenario: Open from the panel
- **WHEN** the user selects `a.lua` in the panel
- **THEN** `a.lua` opens with the cursor on its first pending change

### Requirement: Side-by-side view
For the current file the user SHALL be able to switch between the inline overlay and a side-by-side diff of baseline and current content, and back. Keep and undo SHALL work in both views.

#### Scenario: Toggle the view
- **WHEN** the user toggles the view on a file with pending changes
- **THEN** a read-only baseline window and the file's window are shown in diff mode, and toggling again restores the inline overlay

### Requirement: Binary and oversized files
Binary files and files above a configurable size limit SHALL be listed with their status but without an inline overlay, and SHALL be kept or undone as whole files only.

#### Scenario: Binary file changed
- **WHEN** an agent overwrites `logo.png`
- **THEN** the panel lists it as binary, and keeping or undoing it acts on the whole file

### Requirement: Command and change notifications
The plugin SHALL expose an `:Agentdiff` command with subcommands for every action and completion of their names, and SHALL fire a `User` autocommand with pattern `AgentdiffChanged` whenever the set of pending changes changes.

#### Scenario: Subcommand completion
- **WHEN** the user types `:Agentdiff ` and requests completion
- **THEN** the subcommand names are offered

#### Scenario: Change event
- **WHEN** a new agent change is detected or a change is kept or undone
- **THEN** a `User AgentdiffChanged` autocommand fires

### Requirement: Pending status of a path
The plugin SHALL provide a `path_status(path)` API returning `"file"` for a file with pending changes (including created and deleted files), `"dir"` for a directory that contains such a file at any depth, and nil otherwise, cheap enough to call for every line of a file tree. It SHALL define `AgentdiffTreeFile` and `AgentdiffTreeDir` highlight groups, linking to `DiagnosticWarn` by default.

#### Scenario: File and its parents
- **WHEN** an agent changed `src/app/main.lua`
- **THEN** `path_status` returns "file" for that file, "dir" for `src/app` and `src`, and nil for `src/other.lua`

#### Scenario: Nothing pending
- **WHEN** every change has been kept or undone
- **THEN** `path_status` returns nil for every path

### Requirement: Statusline summary
The plugin SHALL provide a statusline component that returns a summary of pending changes (number of files and changes), and an empty string when nothing is pending.

#### Scenario: Summary with pending changes
- **WHEN** three files have seven pending changes in total
- **THEN** the component returns a summary naming 3 files and 7 changes

#### Scenario: Nothing pending
- **WHEN** no change is pending
- **THEN** the component returns an empty string

### Requirement: Staging keeps changes
When review starts and whenever the project's index changes, every pending change (file or hunk) whose current content is staged SHALL be kept, as in VS Code where staging keeps pending edits; a deletion counts as staged once the file is gone from the index and was tracked before. Committing therefore keeps whatever the commit stages. Unstaged parts SHALL stay pending, and unstaging SHALL NOT make anything pending. The `keep_on_stage` option (default on) SHALL turn this off.

#### Scenario: Stage a file
- **WHEN** a file has pending agent changes and the user stages it in lazygit (`git add`)
- **THEN** nothing is pending for that file and the file is unchanged on disk

#### Scenario: Stage one hunk
- **WHEN** an agent changed two regions of a file and the user stages only one of them
- **THEN** only the other region is still pending

#### Scenario: Commit all
- **WHEN** a file has pending agent changes and the user runs `git commit -a`
- **THEN** nothing is pending for that file after the commit

#### Scenario: Unstage after staging
- **WHEN** the user stages a pending change and then unstages it, or unstages saved work of their own
- **THEN** nothing becomes pending

#### Scenario: Committed before review started
- **WHEN** pending changes were committed while Neovim was closed (or by a version without staging-keeps) and review starts
- **THEN** those changes are kept and nothing is pending for them

#### Scenario: Committed deletion
- **WHEN** the agent deleted a tracked file and the deletion was committed
- **THEN** the deletion is kept; a deleted file that was never tracked stays pending

#### Scenario: Staging keeps disabled
- **WHEN** `keep_on_stage` is off and an agent edit is staged
- **THEN** the edit is still pending

### Requirement: Keep and undo end a conflict
On a conflicted file, keep SHALL accept the agent's version, the agent's content winning only where it overlaps the user's unsaved edits and the user's other unsaved edits staying unsaved; undo SHALL undo the agent's changes on disk and keep the user's unsaved edits. Either way the file SHALL no longer be conflicted or pending, and its buffer SHALL match the disk, so writing it raises no "changed since reading" prompt.

#### Scenario: Keep a conflicted file
- **WHEN** a file is conflicted (the agent rewrote line 3, the user has unsaved edits on lines 3 and 8) and the user keeps it
- **THEN** line 3 holds the agent's content, line 8 the user's unsaved edit, nothing is pending, the file-tree mark is gone, and checking the file against the disk reports no change

#### Scenario: Undo a conflicted file
- **WHEN** the user undoes a conflicted file
- **THEN** the disk is back to the baseline, the user's unsaved edits are kept, nothing is pending and the file-tree mark is gone

### Requirement: Reset a project's review
The plugin SHALL provide a reset action and `:Agentdiff reset` subcommand that, after confirmation, discards the current project's store and rebuilds its baseline from the current disk content, so nothing is pending. Other projects' stores SHALL be unaffected.

#### Scenario: Reset the current project
- **WHEN** a project has pending changes and the user runs `:Agentdiff reset` and confirms
- **THEN** nothing is pending, review continues, and later agent changes are shown as usual

#### Scenario: Other projects untouched
- **WHEN** the user resets one project
- **THEN** the pending changes stored for other projects are still there

### Requirement: Optional integration modules
The plugin SHALL ship integrations with other plugins as separate modules under `agentdiff.integrations`. They SHALL be loaded only when the host requires them, SHALL NOT require the other plugin until the host calls them, and the core plugin SHALL work the same whether or not any integration is used.

#### Scenario: Not loaded by default
- **WHEN** the host calls `setup()` and never requires an integration module
- **THEN** no `agentdiff.integrations.*` module is loaded and neither neo-tree, oil nor grug-far is required

#### Scenario: Other plugin absent
- **WHEN** the host requires an integration module while the plugin it integrates with is not installed
- **THEN** requiring the module succeeds and agentdiff keeps working

### Requirement: Neo-tree integration
`agentdiff.integrations.neotree` SHALL provide a neo-tree component that shows a review mark (with the `AgentdiffTreeFile` / `AgentdiffTreeDir` highlights) on files with pending changes and on collapsed directories containing one, a function returning neo-tree's default renderers with that component added next to `git_status`, and a setup helper that refreshes the tree when pending changes change.

#### Scenario: Component marks a changed file
- **WHEN** a file has pending changes and neo-tree renders it with the component
- **THEN** the component returns the review icon with the `AgentdiffTreeFile` highlight, and nothing for files without pending changes

#### Scenario: Expanded directory
- **WHEN** a directory contains a changed file and is expanded in neo-tree
- **THEN** the component shows no mark on the directory

### Requirement: Oil integration
`agentdiff.integrations.oil` SHALL provide a setup helper that claims, before and after, every path touched by oil.nvim's file actions (create, delete, move, copy), so they are never shown as agent changes.

#### Scenario: Rename in oil
- **WHEN** the oil integration is set up and the user renames a file in oil
- **THEN** neither the old nor the new path is shown as a pending change

### Requirement: grug-far integration
`agentdiff.integrations.grug_far` SHALL provide an `on_before_edit_file` hook for grug-far that claims each file right before grug-far rewrites it and then lets grug-far continue.

#### Scenario: Project-wide replace
- **WHEN** grug-far runs a replacement with the hook configured
- **THEN** every replaced file is claimed, grug-far's edit proceeds, and none of the files is shown as a pending change

### Requirement: Attribution modes
The `attribution` option SHALL choose how disk changes get their author, for every project: `"hooks"` (the default; only what an agent hook reported is the agent's) or `"writer"` (anything Neovim didn't make is the agent's). An unknown value SHALL be rejected by `setup()`.

#### Scenario: Default mode
- **WHEN** the host calls `setup()` without `attribution`
- **THEN** review behaves as in the hooks mode

#### Scenario: Unknown mode
- **WHEN** the host calls `setup({ attribution = "magic" })`
- **THEN** setup reports an error naming the valid modes

### Requirement: Hooks attribution
In the hooks mode, a change Neovim did not make SHALL be the agent's only when an agent hook reported that file shortly before or after the change. Every other such change SHALL be folded into the baseline without becoming pending. Neovim's own writes, claims, staging-keeps and conflicts SHALL behave as in the writer mode.

#### Scenario: Reported agent edit
- **WHEN** the hooks mode is on and Claude Code edits `src/a.lua` with its Edit tool
- **THEN** the edit is shown as a pending change

#### Scenario: Generated file
- **WHEN** the hooks mode is on and a code generator in another pane rewrites `src/gen.lua`
- **THEN** nothing is shown as pending

#### Scenario: Agent shell edit
- **WHEN** the hooks mode is on and the agent changes a file by running `sed -i` in its shell
- **THEN** nothing is shown as pending, as in VS Code

#### Scenario: A report covers one change
- **WHEN** a reported edit has been shown as pending and later a script outside Neovim changes the same file
- **THEN** the script's change is not attributed to the agent

### Requirement: Hook reporter
The plugin SHALL provide a hook reporter command that an agent CLI runs on file edits. It SHALL read the hook payload from stdin, record the edited files in the store of each reviewed project they belong to, ignore payloads that are not file edits and files outside reviewed projects, print nothing, and always exit with status 0, so it never blocks or fails the agent's tool call. It SHALL work whether or not Neovim is running.

#### Scenario: Neovim closed
- **WHEN** Neovim is not running, the agent edits a file of a reviewed project, and Neovim is started later in the hooks mode
- **THEN** the edit is shown as pending

#### Scenario: Not a file edit
- **WHEN** the reporter receives a payload for a shell or read tool, or malformed JSON
- **THEN** it records nothing, prints nothing and exits with status 0

### Requirement: Claude Code adapter
The Claude Code adapter SHALL report the files edited by the `Edit`, `Write`, `MultiEdit` and `NotebookEdit` tools (from `tool_input.file_path`, or `tool_input.notebook_path`), as "pre" on `PreToolUse` and "post" on `PostToolUse`, resolving relative paths against the payload's `cwd`.

#### Scenario: Edit payload
- **WHEN** the reporter receives a Claude Code `PreToolUse` payload for `Edit` with `tool_input.file_path = "/p/src/a.lua"`
- **THEN** it records `/p/src/a.lua` for the project `/p`

### Requirement: Copilot CLI adapter
The Copilot CLI adapter SHALL report the files edited by Copilot CLI's file tools (`edit`, `create`, and equivalents such as `str_replace_editor`, `write`, `apply_patch`), from both its camelCase payloads (`toolName`, `toolArgs` as an object or a JSON string) and its VS Code-style payloads (`tool_name`, `tool_input`), taking the path from `path`, `file_path`, `filePath` or `filename`, or from the file headers of a patch.

#### Scenario: camelCase payload
- **WHEN** the reporter receives `{ "toolName": "edit", "toolArgs": "{\"path\":\"src/a.lua\"}", "cwd": "/p" }`
- **THEN** it records `/p/src/a.lua`

#### Scenario: Patch payload
- **WHEN** the reporter receives an `apply_patch` payload whose patch updates `src/a.lua` and adds `src/b.lua`
- **THEN** it records both files

### Requirement: Installing hooks
`:Agentdiff hooks install|uninstall [harness] [scope]` and the matching Lua functions SHALL manage agentdiff's hook for `claude`, `copilot` or all harnesses, at user scope (the default) or project scope. Install SHALL merge into the CLI's existing configuration without dropping other settings, back the file up before its first change, put the absolute store location in the hook command, and change nothing when already installed. Uninstall SHALL remove only agentdiff's hook.

#### Scenario: Install into existing settings
- **WHEN** `~/.claude/settings.json` has other settings and hooks and the user runs `:Agentdiff hooks install claude`
- **THEN** the file keeps them, gains agentdiff's PreToolUse and PostToolUse hooks, and a backup of the original exists

#### Scenario: Install twice
- **WHEN** the user installs the same hook twice
- **THEN** the configuration is the same as after the first install

#### Scenario: Uninstall
- **WHEN** the user runs `:Agentdiff hooks uninstall claude`
- **THEN** agentdiff's hooks are gone and every other setting and hook is unchanged

### Requirement: Hooks status
`:Agentdiff hooks status` and the matching Lua function SHALL show, per harness, whether and where agentdiff's hook is installed and when it last reported an edit for the current project.

#### Scenario: Status after an edit
- **WHEN** the hook is installed and the agent has edited a file
- **THEN** `:Agentdiff hooks status` shows where the hook is installed and the time of the last report

### Requirement: Missing hook notice
When review starts in the hooks mode and no agent hook is installed for any harness, at user scope or for the project, the user SHALL be told once per Neovim instance how to install one or how to switch to the writer mode.

#### Scenario: No hook installed
- **WHEN** review starts in the hooks mode and neither Claude Code nor Copilot CLI has agentdiff's hook installed, at user scope or for the project
- **THEN** a notice says to run `:Agentdiff hooks install` or set `attribution = "writer"`, and it is not repeated when review restarts in the same Neovim

#### Scenario: Hook installed
- **WHEN** review starts in the hooks mode and agentdiff's hook is installed for Claude Code at user scope or for Copilot CLI in the project
- **THEN** no notice is shown
