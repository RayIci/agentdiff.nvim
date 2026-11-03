# Design

## Context

See proposal.md for motivation. The modular layout from the previous change gives the extension points: `attribution/` (modes with `classify(s, changes, ctx)` and a registry, today only `writer`), `harness/` (adapter interface and empty registry), `detect/poller` (asks `attribution.active(s)`). Hook facts, from the CLIs' documentation:

| | Claude Code | Copilot CLI |
|---|---|---|
| Events | `PreToolUse`, `PostToolUse` (JSON on stdin) | `preToolUse`, `postToolUse` (camelCase config) or `PreToolUse`/`PostToolUse` (VS Code style) |
| File tools | `Edit`, `Write`, `MultiEdit`, `NotebookEdit` | `edit`, `create` (the CLI maps `str_replace_editor`, `apply_patch` to Edit for Claude-style configs) |
| Path field | `tool_input.file_path` (`notebook_path` for notebooks) | not documented; `toolArgs` (object or JSON string) or `tool_input` |
| Config | `~/.claude/settings.json`, `.claude/settings.local.json` | `~/.copilot/hooks/*.json`, `.github/hooks/*.json` (also reads `.claude/settings*.json`) |
| Blocking | `PostToolUse` can't block; `PreToolUse` blocks on exit 2 | `preToolUse` command hooks are fail-closed on any non-zero exit or crash |

## Goals / Non-Goals

**Goals:** positive attribution for Claude Code and Copilot CLI, installable from Neovim, working with Neovim closed and with several instances; zero risk of breaking the agent's tool calls.

**Non-Goals:** per-project or per-process mode selection (later modes), Codex (later adapter), attributing agent shell commands, approving edits before they land.

## Decisions

### D1. The journal: one file per report in the store
`<store>/agent/<ms>-<pid>-<n>.json` = `{ "time": ms, "harness": "claude", "phase": "pre"|"post", "paths": ["src/a.lua", …], "session": "…" }` with project-relative paths. One file per report means concurrent hook processes never contend (no locking, no partial appends). `core/journal.lua` owns `add(dir, report)`, `reported(dir, since)` (path → newest report time), `take(dir, paths)` (consume), `gc(dir, ttl)` and `last(dir)` (newest report per harness, for status). Reports older than `report_ttl` (60 s) are deleted by `gc`.

### D2. The reporter: `bin/agentdiff-hook.lua`, run with `nvim -l`
Command line: `nvim --headless -u NONE -l <plugin>/bin/agentdiff-hook.lua <harness> <state_dir>`. It prepends `<plugin>/lua` to `package.path`, reads stdin, decodes JSON, asks the named adapter (falling back to every adapter) for a report, and for each path finds the project root (`vim.fs.root(path, ".git")`, else the payload's `cwd`), then the store `<state_dir>/<sha256(root):sub(1,16)>`, exactly as `core/store.open` derives it. It writes a report only when that store exists (a reviewed project). Everything runs inside `pcall`; it prints nothing and calls `os.exit(0)` in all cases. Neovim is the only dependency, so no `jq` or Python is needed; startup without config is ~30–80 ms.

### D3. Hooks mode: reported → agent, otherwise → user after a short wait
`attribution/hooks.lua` implements `classify`:
- forced modes, `s.writing`, unreviewable paths and claims as in `writer`;
- a path with a report newer than `now - report_window` (10 s) → **agent**, and its reports are consumed (`journal.take`);
- otherwise the path waits `hook_settle` (1500 ms, the time a `PostToolUse` report needs to arrive when a CLI runs no pre hook), then becomes **user** (folded into the baseline).

A "post" report arriving after its "pre" report was consumed is dropped by `take`'s rule that a path consumed at `t` ignores reports up to `t + 2 s`, so a late duplicate doesn't attribute the next unrelated change. git-guard and discard detection aren't needed: anything unreported is the user's anyway. Staging-keeps runs in `detect/git` as before.

### D4. Adapters
`harness/claude.lua` and `harness/copilot.lua` implement the interface. Both parse defensively:
- tool name from `tool_name` / `toolName`;
- arguments from `tool_input` / `toolArgs`, decoding a JSON string;
- path from `file_path`, `path`, `filePath`, `filename`, `notebook_path`, or patch headers (`*** Update File: x`, `*** Add File: x`, `*** Delete File: x`, `+++ b/x`);
- phase from `hook_event_name` / the event the hook was installed for (passed as a third argument);
- relative paths resolved against `cwd`.

Their tool lists differ (Claude: `Edit|Write|MultiEdit|NotebookEdit`; Copilot: `edit|create|str_replace_editor|write|apply_patch`) and so do their install targets.

### D5. Installing: merge, mark, back up
`harness/settings.lua` reads a JSON file (missing → `{}`), lets the adapter add or remove its entries, and writes it back with `vim.json.encode(…, { indent = "  ", sort_keys = true })` after copying the original to `<file>.agentdiff.bak` (only once). agentdiff's entries are recognised by the marker `agentdiff-hook.lua` in the command, which makes install idempotent and uninstall precise.

| Harness | user scope | project scope | Entries |
|---|---|---|---|
| claude | `~/.claude/settings.json` | `<root>/.claude/settings.local.json` | `hooks.PreToolUse` and `hooks.PostToolUse`: `{ matcher, hooks = [{ type = "command", command, timeout = 10 }] }` |
| copilot | `~/.copilot/hooks/agentdiff.json` (own file) | `<root>/.github/hooks/agentdiff.json` | `{ version = 1, hooks = { preToolUse = [{ type = "command", bash, matcher, timeoutSec = 10 }], postToolUse = … } }` |

The plugin's own path comes from the location of `harness/init.lua` (`debug.getinfo`), so the command points at the installed copy. Adapters take `opts.home` and `opts.root` so tests install into temp directories.

### D6. Commands and API
`actions/hooks.lua` provides `install(harness?, scope?)`, `uninstall(…)`, `status()`; the entry point exposes them as `hooks_install`, `hooks_uninstall`, `hooks_status`, and `:Agentdiff hooks <install|uninstall|status> [claude|copilot|all] [user|project]` with completion. Subcommands now receive their extra arguments: `fn(range, args)`.

## Risks / Trade-offs

- [Copilot's argument field differs from every guess] → the parser tries every known shape and patch headers; `hooks status` shows the last report per harness, so a silent adapter is visible.
- [Copilot `preToolUse` hooks are fail-closed] → the reporter can't fail: `pcall` around everything, `os.exit(0)` always, no output.
- [Rewriting `~/.claude/settings.json` reorders keys] → the backup is kept, and only agentdiff's entries change.
- [In hooks mode, an agent's shell edits are invisible] → intended (VS Code behaves the same); documented.
- [Both hooks installed (user and project), or Copilot also reading `.claude/settings.local.json`] → duplicate reports are harmless; a path is consumed once.

## Migration Plan

Opt-in. With the default `attribution = "writer"` nothing changes; hooks are installed only by the user. Uninstall removes them; deleting the store's `agent/` directory forgets pending reports.
