# Proposal

## Why

`panel.size` takes one value: a fixed number of columns/rows or a share of the editor. Users want rules like "30% of the width, but at least 45 columns", which no single value expresses.

## What Changes

- `panel.size` also accepts a function. It is called with `{ position, total }` (`total`: the editor's columns for a left/right panel, its usable rows for top/bottom) each time the panel opens and when the editor is resized, and returns any value `size` accepts (columns/rows, a fraction, or `"N%"`). An invalid result or an error falls back to the default `40`.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `agent-change-review`: the panel's size can be computed by a function.

## Impact

- Code: `config.lua` (validation), `ui/panel.lua` (`M.size`).
- Tests: a function size, recomputed on resize, and the fallback.
- Docs: README, `doc/agentdiff.txt`.
