# Tasks

Each group ends with `make test`, `make fmt-check` and lua_ls clean, and is committed on its own.

## 1. Journal and option

- [x] 1.1 Add `core/journal.lua` (add, reported, take, gc, last) with the one-file-per-report layout (D1); verify unit tests for concurrent adds, consumption, the late-duplicate rule and gc
- [x] 1.2 Add the `attribution` option validated against the attribution registry, and make `attribution.active(s)` return the configured mode; verify tests for "Default mode" and "Unknown mode", and update the public-surface test

## 2. Adapters

- [x] 2.1 Add `harness/claude.lua` `parse` (D4); verify a test for "Edit payload" plus `Write`, `MultiEdit`, `NotebookEdit`, relative paths, and non-edit tools returning nil
- [x] 2.2 Add `harness/copilot.lua` `parse`; verify tests for "camelCase payload", "Patch payload", the VS Code-style payload, and non-edit tools

## 3. Reporter and hooks mode

- [x] 3.1 Add `bin/agentdiff-hook.lua` (D2); verify tests that run it as a real `nvim -l` process: a report lands in the right project's store, "Not a file edit" (exit 0, no output, nothing recorded), a file outside reviewed projects records nothing
- [x] 3.2 Add `attribution/hooks.lua` (D3); verify tests for "Reported agent edit", "Generated file", "Agent shell edit", "A report covers one change" and "Neovim closed"

## 4. Installing

- [x] 4.1 Add `harness/settings.lua` and the adapters' install, uninstall and status (D5); verify tests for "Install into existing settings", "Install twice" and "Uninstall" for both harnesses at both scopes, in temp directories
- [x] 4.2 Add `actions/hooks.lua`, the public functions and `:Agentdiff hooks …` with completion (D6); verify tests for "Status after an edit", the subcommand completion and the public-surface test

## 5. Docs and end-to-end

- [x] 5.1 Document the hooks mode, the reporter, the adapters and the commands in the README, `doc/agentdiff.txt`, `docs/attribution.md` and `docs/extending.md`; verify the API doc tests, `:helptags` and Mermaid parsing
- [x] 5.2 Run the reporter by hand with a real Claude Code payload shape and a Copilot payload shape against a temp store, and start Neovim with a full configuration using `attribution = "hooks"`; verify a reported change shows as pending and an unreported one doesn't

## Workflow follow-up

- Sync the `agent-change-review` delta and archive this change.
