# Proposal

## Why

agentdiff decides who changed a file by elimination: anything Neovim didn't write is the agent's. That catches every agent with no setup, but it also blames the agent for everything else that writes into the project: code generators, build output, files created in a terminal or by a file explorer, scaffolding commands. Agent CLIs can report exactly which files they edit through their hook systems (Claude Code and Copilot CLI both have `PreToolUse`/`PostToolUse` hooks), so the plugin can review only what an agent reported, the way VS Code reviews only edits its agent made.

## What Changes

- Add an `attribution` option: `"writer"` (today's behaviour, the default) or `"hooks"`, a global switch. Attribution modes are pluggable, so per-project or per-process selection can be added later.
- Add the **hooks** attribution mode: a disk change is the agent's only when an agent hook reported that file; every other change Neovim didn't make is folded into the baseline silently. Neovim's own writes, claims and staging-keeps work as before.
- Add a hook reporter: a command the agent CLI runs on each file edit. It reads the hook payload from stdin, records the edited paths in the project's store (no running Neovim needed), prints nothing, always exits successfully, and never slows or blocks the agent noticeably.
- Add harness adapters for **Claude Code** (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`) and **Copilot CLI** (`edit`, `create` and equivalents). Codex can follow as another adapter.
- Add `:Agentdiff hooks install|uninstall|status [harness] [user|project]` and matching Lua functions. Install merges agentdiff's hook into the CLI's configuration (backing it up first), puts the absolute store location in the hook command, and is idempotent. Status shows where each hook is installed and when it last reported an edit.
- Agent edits made through shell commands (`sed -i`, scripts run by the agent) are not reported by hooks and so are not reviewed, as in VS Code.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `agent-change-review`: adds attribution modes, the hooks mode, the hook reporter, the Claude Code and Copilot CLI adapters, and the hooks commands; "Agent changes become pending reviews" now describes the writer mode.

## Impact

- Code: `attribution/hooks.lua`, `core/journal.lua`, `harness/claude.lua`, `harness/copilot.lua`, `harness/settings.lua` (JSON config merging), `bin/agentdiff-hook.lua`, `actions/hooks.lua`; the `attribution` option; a `hooks` subcommand (which now receives arguments).
- Writes to agent CLI configuration only when the user runs `hooks install` (user level: `~/.claude/settings.json`, `~/.copilot/hooks/agentdiff.json`; project level: `.claude/settings.local.json`, `.github/hooks/agentdiff.json`).
- The public surface grows (new functions, subcommand and option); everything existing behaves the same with the default `attribution = "writer"`.
- No new dependencies: the reporter runs with `nvim -l`.
