# agentdiff documentation

How agentdiff works under the hood. For setup, options and the API, see the
[top-level README](../README.md).

| Document | What it covers |
|---|---|
| [architecture.md](architecture.md) | big picture, module map, layers, the three texts per file (B, O, D), store layout, session state, lifecycle |
| [attribution.md](attribution.md) | the author rule, how every disk change gets an author, sequence diagrams for every scenario (agent edit, your save, unsaved buffers, conflicts, undo, git) |
| [detection.md](detection.md) | the poll loop, timing budget, settle period, shell commands, several Neovim instances, startup |
| [merge3.md](merge3.md) | the three-way merge, with worked examples |
| [review-ui.md](review-ui.md) | the overlay, navigation order, keep/undo (including partial ranges), created/deleted files, panel, side-by-side, statusline, file tree |
| [testing.md](testing.md) | how the headless suite works, what each spec file covers, charts of the test distribution |
| [extending.md](extending.md) | adding an attribution mode, a harness adapter or an integration |
| [decisions.md](decisions.md) | comparison with VS Code's agent mode and the reasoning behind the main design choices |

Reference documentation for users is in [`doc/agentdiff.txt`](../doc/agentdiff.txt) (`:help agentdiff`).

All diagrams are [Mermaid](https://mermaid.js.org/) and render on GitHub.
