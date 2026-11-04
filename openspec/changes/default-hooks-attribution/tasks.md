# Tasks

Each group ends with `make test`, `make fmt-check` and lua_ls clean, and is committed on its own.

## 1. Default and notice

- [x] 1.1 Make `"hooks"` the default of `attribution`; start the test helper in the writer mode explicitly; verify the "Default mode" test (setup without `attribution` uses the hooks mode) and the public-surface test
- [ ] 1.2 Add `hooks.any_installed()` and the one-time notice at start in the hooks mode; verify tests for "No hook installed" (shown once, not repeated on another project) and no notice when a hook is installed or in the writer mode

## 2. Docs

- [ ] 2.1 Present the hooks mode as the default in the README, `doc/agentdiff.txt` and `docs/attribution.md`, with the writer mode as the zero-setup alternative; verify the API doc tests, `:helptags` and Mermaid parsing

## Workflow follow-up

- Sync the `agent-change-review` delta and archive this change.
