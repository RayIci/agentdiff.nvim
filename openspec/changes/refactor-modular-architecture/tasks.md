# Tasks

Each group ends with `make test`, `make fmt-check` and lua_ls clean, and is committed on its own (moves with `git mv` in a commit separate from content edits).

## 1. Safety net

- [x] 1.1 Add `tests/layers_spec.lua`: parse every `require("agentdiff.…")` under `lua/agentdiff/`, map modules to layers (D1) and fail on upward dependencies, with an allow-list of today's violations; verify it passes now and fails when a new upward require is added on purpose
- [x] 1.2 Record the public surface (every function on `require("agentdiff")`, every `:Agentdiff` subcommand, every option, every highlight group) in a test; verify it passes before any move

## 2. core/

- [x] 2.1 `git mv` `merge`, `store`, `util`, `session` into `core/` and update every require (code and tests); verify the suite passes
- [x] 2.2 Split `review.lua` into `core/text.lua`, `core/state.lua`, `core/baseline.lua` and `core/events.lua` (D2, D3); verify the suite passes
- [x] 2.3 Replace `state.refresh → render` with the event bus: overlay and hint subscribe to `"refreshed"`; remove the `review → render` and `panel → detect` violations from the allow-list; verify the suite and the layer test pass

## 3. attribution/ and detect/

- [x] 3.1 Move the claim journal to `core/claims.lua` (store data the baseline update consumes) and shell recognition to `attribution/shell.lua`; add `attribution/init.lua` with the interface and registry (D4); verify the suite passes
- [x] 3.2 Extract the classification from `detect.handle` into `attribution/writer.lua` behind the interface, with git helpers passed in; verify the suite passes
- [x] 3.3 Split the rest of `detect.lua` into `detect/poller.lua` and `detect/git.lua`; verify the suite passes

## 4. editor/ and actions/

- [x] 4.1 Move `buffers.lua` to `editor/buffers.lua`; verify the suite passes
- [x] 4.2 Split `actions.lua` into `actions/navigate.lua`, `actions/review.lua` and `actions/resolve.lua`; move on/off + epoch to `actions/onoff.lua` and reset to `actions/reset.lua`; verify the suite passes

## 5. ui/

- [x] 5.1 Split `render.lua` into `ui/overlay.lua`, `ui/hint.lua`, `ui/highlights.lua`; move `panel` and `sidebyside` into `ui/`; add `ui/status.lua` (`status`, `path_status`, `files`); verify the suite passes

## 6. Thin entry point and extension points

- [x] 6.1 Extract `command.lua` and `keymaps.lua`; reduce `init.lua` to setup/start/stop orchestration and re-exports; verify the public-surface test passes unchanged
- [x] 6.2 Add `harness/init.lua` with the adapter interface and an empty registry (D5); verify a test registers a fake adapter and gets it back

## 7. Integrations

- [x] 7.1 Add `integrations/neotree.lua` (component, renderers, setup); verify tests for "Component marks a changed file" and "Expanded directory"
- [x] 7.2 Add `integrations/oil.lua` (paths, setup); verify a test for "Rename in oil" driving the `OilActionsPre`/`OilActionsPost` events
- [x] 7.3 Add `integrations/grug_far.lua` (`on_before_edit_file`); verify a test for "Project-wide replace" (claims recorded, `on_finish("success")` called)
- [x] 7.4 Verify tests for "Not loaded by default" (`package.loaded` after setup) and "Other plugin absent" (requiring each integration without neo-tree/oil/grug-far on the runtimepath)

## 8. Strict layering and docs

- [x] 8.1 Empty the layer test's allow-list; verify it passes
- [x] 8.2 Update `docs/architecture.md` (module map, layer diagram), `README.md` and `doc/agentdiff.txt` (integration modules replace the copy-paste recipes); add `docs/extending.md` (adding an attribution mode, a harness adapter, an integration); verify the API doc tests pass, `:helptags` reports no duplicates and every Mermaid block parses
- [ ] 8.3 Start Neovim headless with a full configuration that uses the plugin, with this checkout first on the runtimepath; verify review becomes ready, keymaps are mapped and `:messages` is empty

## Workflow follow-up

- Archive this change after the tasks are done, syncing the `agent-change-review` delta.
- Next change here: hooks attribution (`attribution/hooks.lua`, journal, `claude` and `copilot` adapters, `:Agentdiff hooks install|uninstall|status`).
