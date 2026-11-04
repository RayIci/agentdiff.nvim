# Proposal

## Why

The hooks attribution mode reviews exactly what agents report through their hooks, so code generators, build output, file explorers and other programs writing into the project are never shown as agent changes. That is the behaviour VS Code users expect, and it is the mode agentdiff should start in. The writer mode stays for agents without an adapter and for reviewing agent shell edits, but as an opt-in.

## What Changes

- **BREAKING** The default of the `attribution` option becomes `"hooks"`. Hosts that relied on the writer mode without setting the option must set `attribution = "writer"`.
- When review starts in the hooks mode and no agent hook is installed for any harness (at user scope or for the project), agentdiff shows a one-time notice per Neovim instance telling the user to run `:Agentdiff hooks install` or to set `attribution = "writer"`, so a new install doesn't silently review nothing.
- Docs present the hooks mode as the default and the writer mode as the zero-setup alternative.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `agent-change-review`: the default attribution mode is the hooks mode, and a missing hook is announced; "Agent changes become pending reviews" describes the writer mode only.

## Impact

- Code: `config.lua` (default), `init.lua` (the notice at start), `actions/hooks.lua` (an "is any hook installed" check).
- Tests: the test helper starts the plugin in the writer mode explicitly (the existing detection tests are writer-mode tests); the default-mode test and the public-surface test change; a test for the notice.
- Docs: README, `doc/agentdiff.txt`, `docs/attribution.md`.
- Existing users who never set `attribution` see only agent edits their CLIs report, after installing the hooks.
