# Spec Delta

## MODIFIED Requirements

### Requirement: Agent changes become pending reviews
In the writer attribution mode (the default), any change to a file in the project that Neovim did not make SHALL be treated as an agent change. A file's pending changes SHALL be exactly the difference between its baseline (the last agreed content) and its current content, and SHALL stay pending until kept or undone. Detection SHALL need no configuration of the agent.

#### Scenario: Agent edit from another tmux pane
- **WHEN** Claude Code running in another tmux pane edits `lua/foo.lua`
- **THEN** that edit appears in Neovim as a pending change of `lua/foo.lua`

#### Scenario: File never opened in Neovim
- **WHEN** an agent edits a project file that has no Neovim buffer
- **THEN** the file is listed with its pending changes and opening it shows them inline

#### Scenario: Any harness
- **WHEN** the same edit is made by Copilot CLI or Codex instead of Claude Code, with no hooks or settings added to either
- **THEN** it is shown as a pending change in the same way

## ADDED Requirements

### Requirement: Attribution modes
The `attribution` option SHALL choose how disk changes get their author, for every project: `"writer"` (the default; anything Neovim didn't make is the agent's) or `"hooks"` (only what an agent hook reported is the agent's). An unknown value SHALL be rejected by `setup()`.

#### Scenario: Default mode
- **WHEN** the host calls `setup()` without `attribution`
- **THEN** review behaves as in the writer mode

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
