# Spec Delta

## MODIFIED Requirements

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

### Requirement: Attribution modes
The `attribution` option SHALL choose how disk changes get their author, for every project: `"hooks"` (the default; only what an agent hook reported is the agent's) or `"writer"` (anything Neovim didn't make is the agent's). An unknown value SHALL be rejected by `setup()`.

#### Scenario: Default mode
- **WHEN** the host calls `setup()` without `attribution`
- **THEN** review behaves as in the hooks mode

#### Scenario: Unknown mode
- **WHEN** the host calls `setup({ attribution = "magic" })`
- **THEN** setup reports an error naming the valid modes

### Requirement: Hooks attribution
In the hooks mode, a change Neovim did not make SHALL be the agent's only when an agent hook reported that file shortly before or after the change. Every other such change SHALL be folded into the baseline without becoming pending. Neovim's own writes, claims, staging-keeps and conflicts SHALL behave as in the writer mode. When review starts in the hooks mode and no agent hook is installed for any harness, the user SHALL be told once per Neovim instance how to install one or how to switch to the writer mode.

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

#### Scenario: No hook installed
- **WHEN** review starts in the hooks mode and neither Claude Code nor Copilot CLI has agentdiff's hook installed, at user scope or for the project
- **THEN** a notice says to run `:Agentdiff hooks install` or set `attribution = "writer"`, and it is not repeated when another project is opened in the same Neovim
