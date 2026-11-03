# Proposal

## Why

agentdiff grew as 14 flat modules where concerns are tangled: `review.lua` (the review state) calls the overlay renderer directly, `detect.lua` mixes the poll loop with every attribution rule (claims, git-guard, discards, staging, settle), and `init.lua` wires everything by hand. The next feature, attribution by per-harness hooks, needs a second attribution mode and one adapter per agent CLI, and more modes and harnesses are planned (auto-selection, Codex). Without explicit extension points each of those would be edits scattered across `detect`, `review` and `init`. This change restructures the code so that adding an attribution mode, a harness or an integration is adding one file.

## What Changes

- Restructure `lua/agentdiff/` into layers with a one-way dependency rule: `core/` (merge, store, session, review state, baseline updates, change events), `attribution/` (who changed a file), `detect/` (when to look: poller, git watchers), `editor/` (Neovim buffer integration), `actions/` (keep, undo, navigation, resolve, reset, on/off), `ui/` (overlay, hint, panel, side-by-side, status), `integrations/`, plus thin `init.lua`, `command.lua` and `keymaps.lua`.
- Replace direct calls from the review state into the UI with an internal change-event bus; the UI subscribes to it.
- Introduce the **attribution mode** interface and registry, with today's behaviour as the `writer` mode (claims, git-guard, discards, settle).
- Introduce the **harness adapter** interface and registry (no adapters yet; the hooks change adds them).
- Move the host-side recipes into the plugin as optional **integration modules**: the neo-tree component and renderers, the oil claim handler and the grug-far hook. They're loaded only when the host calls them and never require the other plugin on their own.
- Add a test that enforces the dependency rule, and an "extending agentdiff" guide in `docs/`.
- No user-visible behaviour change: the public API, command, options, events, highlights and store format stay the same; every existing test keeps passing (internal `require` paths in tests are updated).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `agent-change-review`: adds the optional integration modules (neo-tree, oil, grug-far) as part of the plugin's public surface. Everything else is unchanged.

## Impact

- Code: every module under `lua/agentdiff/` moves or splits (moved with `git mv` to keep history); tests update their internal `require` paths; new tests for the integrations and the dependency rule.
- Docs: `README.md`, `doc/agentdiff.txt` (integrations section uses the modules), `docs/architecture.md` (module map and layers), new `docs/extending.md`.
- Hosts keep working unchanged; those that copied the documented neo-tree/oil/grug-far recipes can switch to the integration modules.
- No new dependencies; no store migration.
