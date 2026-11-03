# Design

## Context

See proposal.md for motivation. Current state (14 flat modules, 3 800 lines):

| Module | Lines | Requires |
|---|---:|---|
| `init` | 578 | actions buffers claims config detect panel render review session sidebyside store util |
| `actions` | 520 | buffers claims merge render review session sidebyside util |
| `store` | 520 | config util |
| `detect` | 415 | claims merge review session store util |
| `buffers` | 376 | claims merge render review session util |
| `review` | 369 | claims merge **render** session util |
| `merge` | 212 | (none) |
| `render` | 257 | session |
| `panel` | 156 | **detect** review session |
| `session` | 145 | util |
| `config` | 137 | (none) |
| `claims` | 134 | util |
| `sidebyside` | 128 | render review session util |
| `util` | 69 | (none) |

The couplings to break: `review` (state) calls `render` (UI) directly; `panel` (UI) calls `detect`; `detect.handle` holds every attribution rule inline; `init` owns on/off state, reset, the command table, keymaps and the public API at once.

## Goals / Non-Goals

**Goals:**
- One-way layering that a test enforces.
- An attribution-mode interface with today's behaviour as the first mode, so the hooks change only adds `attribution/hooks.lua` (+ journal) and a config option.
- A harness-adapter interface and registry, so each agent CLI is one file.
- Integration recipes shipped as optional plugin modules.
- Zero behaviour change, proven by the existing 134 tests passing at every step.

**Non-Goals:**
- No new attribution mode, no harness adapter, no `attribution` option yet (the hooks change adds them).
- No change to the public API, options, command, events, highlights, store layout or on-disk format.
- No performance work.

## Decisions

### D1. Layers and the dependency rule

```
init.lua · command.lua · keymaps.lua        (wiring: may require anything)
        │
   ┌────┴─────────┬──────────────┐
 actions/        ui/        integrations/    (actions may use editor/; ui never mutates state)
   │              │              │
   └──── editor/ ─┴── detect/ ───┘           (editor: buffers · detect: poller, git)
              │          │
          attribution/   │                   (who changed what)
              │          │
              └── core/ ─┘                   (merge · store · session · state · baseline · events · util)
```

Rule: a module may require only modules in its own layer or below. `core/` requires nothing above it; `ui/` never requires `actions/` or `detect/`; `integrations/` require only the public `agentdiff` module. A test (`tests/layers_spec.lua`) scans `require("agentdiff.…")` calls and fails on any upward dependency.

*Alternative considered:* keep flat files and only extract interfaces. Rejected: the coupling in `review → render` and `panel → detect` is exactly what makes changes spread; the directory layout makes the rule visible and testable.

### D2. Module map

| Old | New |
|---|---|
| `merge.lua` | `core/merge.lua` |
| `store.lua` | `core/store.lua` |
| `util.lua` | `core/util.lua` |
| `session.lua` | `core/session.lua` |
| `config.lua` | `config.lua` (unchanged) |
| `review.lua` `compute`, `refresh`, text helpers | `core/state.lua` (review state per file, `refresh`) and `core/text.lua` (`lines/disp/undisp/buf_lines/is_whole`) |
| `review.lua` `process`, `set_baseline`, `keep_staged` | `core/baseline.lua` (the author rule and baseline writes) |
| `review.lua` `fire_if_changed` | `core/events.lua` (internal bus + `User AgentdiffChanged`) |
| `claims.lua` | `attribution/claims.lua` |
| `detect.lua` classification (claims, guard, discards, settle) | `attribution/writer.lua` |
| (new) | `attribution/init.lua`: interface + registry |
| `detect.lua` timer, focus, shell windows, poll | `detect/poller.lua` |
| `detect.lua` guard/index signatures, `git_produced`, `discarded`, staging, `reconcile` | `detect/git.lua` |
| `buffers.lua` | `editor/buffers.lua` |
| `actions.lua` | `actions/navigate.lua`, `actions/review.lua` (keep/undo, ranges, journal use), `actions/resolve.lua` |
| `init.lua` on/off + epoch | `actions/onoff.lua` |
| `init.lua` reset | `actions/reset.lua` |
| `render.lua` | `ui/overlay.lua` (extmarks), `ui/hint.lua`, `ui/highlights.lua` |
| `init.lua` `status`, `path_status`, `files` | `ui/status.lua` |
| `panel.lua`, `sidebyside.lua` | `ui/panel.lua`, `ui/sidebyside.lua` |
| `init.lua` command table | `command.lua` |
| `init.lua` keymaps | `keymaps.lua` |
| (new) | `harness/init.lua`: interface + registry |
| recipes in `doc/agentdiff.txt` | `integrations/neotree.lua`, `integrations/oil.lua`, `integrations/grug_far.lua` |

`init.lua` keeps `setup`, `start`/`stop` orchestration and re-exports the public API from the modules above, so `require("agentdiff").x` is unchanged.

### D3. Internal event bus instead of state → UI calls

`core/events.lua` exposes `on(name, fn)` and `emit(name, payload)` for in-process subscribers, plus `changed(s)`, which computes the pending signature and fires `User AgentdiffChanged` only when it changed (today's `fire_if_changed`). `core/state.refresh` emits `"refreshed"` with the session and the refreshed paths. `ui/overlay` and `ui/hint` subscribe and redraw. `ui/panel` asks for a re-poll through a callback registered by `init`, not by requiring `detect`.

### D4. Attribution mode interface

```lua
---@class AgentdiffAttributionCtx
---@field mode "poll"|"agent"|"user"   forced author around shell commands, or normal
---@field now integer                  wall-clock ms
---@field guard_moved boolean          HEAD/stash moved since the last poll

---@class AgentdiffAttribution
---@field name string
---@field classify fun(s: AgentdiffSession, changes: AgentdiffChange[], ctx: AgentdiffAttributionCtx): { agent: string[], user: string[], wait: string[] }
---@field reset? fun()                 forget per-session state (suspects)
```

`attribution/init.lua` holds the registry (`register`, `get`) with `writer` registered. `detect/poller` builds the context, calls the active mode (always `writer` in this change), processes `agent`/`user` through `core/baseline`, and schedules a confirmation poll when `wait` isn't empty. Git-specific helpers (`git_produced`, `discarded`) live in `detect/git.lua` and are passed in to `writer` rather than required by it, so future modes can reuse or skip them.

### D5. Harness adapter interface (registry only)

```lua
---@class AgentdiffHarnessReport
---@field phase "pre"|"post"
---@field paths string[]                absolute paths the agent edited
---@field session? string

---@class AgentdiffHarness
---@field name string
---@field parse fun(payload: table): AgentdiffHarnessReport?   nil = not a file edit
---@field install fun(scope: "user"|"project", opts: table): boolean, string?
---@field uninstall fun(scope: "user"|"project", opts: table): boolean, string?
---@field status fun(opts: table): { installed: boolean, where: string? }
```

`harness/init.lua` ships the registry and the interface with no adapters; `claude` and `copilot` arrive with the hooks change.

### D6. Integration modules

Each integration exports plain functions and requires the other plugin lazily, inside the functions that need it:
- `integrations.neotree`: `component(config, node, state)`, `renderers()` (copy of neo-tree's defaults with the component before `git_status`), `setup()` (refresh the filesystem source on `User AgentdiffChanged`).
- `integrations.oil`: `paths(actions)` (pure: oil URLs → paths), `setup()` (claim on `OilActionsPre`/`OilActionsPost`).
- `integrations.grug_far`: `on_before_edit_file(on_finish, file)`.

They implement the recipes documented in `doc/agentdiff.txt`, including the detail that oil's move actions have no `url` field (so the three URL fields are read by key, not with `ipairs`).

### D7. Migration order

Each step is one commit and leaves `make test`, `make fmt-check` and lua_ls clean:
1. Add the layer test (initially lenient: it lists today's violations so later steps can remove them).
2. Move leaf modules (`merge`, `store`, `util`, `session`) into `core/` with `git mv`; update requires.
3. Split `review.lua` into `core/text`, `core/state`, `core/baseline`, `core/events`; add the bus and make the UI subscribe.
4. Extract `attribution/` (claims, writer, registry) from `detect.lua`; split the rest into `detect/poller` and `detect/git`.
5. Move `buffers` to `editor/`; split `actions` and the on/off/reset parts of `init`.
6. Split `render` into `ui/`; move `panel`, `sidebyside`; add `ui/status`.
7. Extract `command.lua` and `keymaps.lua`; `init.lua` becomes orchestration plus re-exports.
8. Add `harness/init.lua`.
9. Add `integrations/`.
10. Make the layer test strict; update docs.

## Risks / Trade-offs

- [A move breaks a lazy `require` that tests don't cover] → the layer test lists every `require("agentdiff.…")`, so a stale path also fails it; the real-config headless startup check runs at the end.
- [The event bus changes redraw timing] → `refresh` still emits synchronously; overlay and hint redraw in the same tick as today.
- [git history becomes harder to follow] → moves use `git mv` in separate commits from content edits, so `git log --follow` works.

## Migration Plan

Internal only. Users see no difference and hosts need no change. Rollback: revert the commits (each step is self-contained).
