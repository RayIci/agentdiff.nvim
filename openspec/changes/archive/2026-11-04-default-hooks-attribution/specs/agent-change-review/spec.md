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

## ADDED Requirements

### Requirement: Missing hook notice
When review starts in the hooks mode and no agent hook is installed for any harness, at user scope or for the project, the user SHALL be told once per Neovim instance how to install one or how to switch to the writer mode.

#### Scenario: No hook installed
- **WHEN** review starts in the hooks mode and neither Claude Code nor Copilot CLI has agentdiff's hook installed, at user scope or for the project
- **THEN** a notice says to run `:Agentdiff hooks install` or set `attribution = "writer"`, and it is not repeated when review restarts in the same Neovim

#### Scenario: Hook installed
- **WHEN** review starts in the hooks mode and agentdiff's hook is installed for Claude Code at user scope or for Copilot CLI in the project
- **THEN** no notice is shown
