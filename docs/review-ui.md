# The review UI

What you see and how each action changes the baseline or the file.

- [The inline overlay](#the-inline-overlay)
- [Navigation order](#navigation-order)
- [Keep and undo](#keep-and-undo)
- [Partial keep and undo](#partial-keep-and-undo)
- [Created, deleted and binary files](#created-deleted-and-binary-files)
- [Panel, side-by-side view, statusline, file tree](#panel-side-by-side-view-statusline-file-tree)

## The inline overlay

The buffer always holds the file exactly as it is on disk. Everything else is
extmarks in the `agentdiff` namespace:

```
  9 │ local function load(path)
    │ local f = io.open(path)                    ← removed line: virt_lines above, AgentdiffDelete
 10 │ local f = assert(io.open(path, "r"))       ← added line: line highlight, AgentdiffAdd
    │                    agent 2/5 · <leader>rk keep · <leader>ru undo   ← hint, right-aligned
 11 │ return f:read("a")
```

```mermaid
flowchart LR
    h["hunk<br/>a: [a_lo, a_hi) baseline<br/>b: [b_lo, b_hi) current"] --> add["rows b_lo … b_hi-1<br/>line_hl_group = AgentdiffAdd"]
    h --> del["baseline lines a_lo … a_hi-1<br/>virt_lines, above row b_lo<br/>(below the last row at end of file)"]
    h --> hint["hint on the hunk nearest the cursor<br/>separate namespace, redrawn on CursorMoved"]
```

- No signs are placed, so gitsigns keeps the sign column.
- The overlay is redrawn 100 ms after the buffer stops changing, and right
  away after detection, keep or undo.
- Conflicted files use `AgentdiffConflict` for their added lines.
- A leftover buffer of a file the agent deleted is shown entirely in
  `AgentdiffDelete`.

## Navigation order

Changes are ordered by file path, then by line. That flat list gives the hint
its "2/5" position and drives `]a` / `[a`:

```mermaid
flowchart LR
    subgraph a["a.lua"]
        a1["change 1<br/>line 3"] --> a2["change 2<br/>line 12"]
    end
    subgraph b["b.lua"]
        b1["change 3<br/>line 7"]
    end
    subgraph c["c.lua (created)"]
        c1["change 4<br/>whole file"]
    end
    a2 -- "]a opens the next file" --> b1 --> c1
    c1 -. "]a wraps (with a notice)" .-> a1
```

`]A` / `[A` move between files, landing on their first change.

## Keep and undo

Both work on the review state of one file: `base` (display baseline lines),
`cur` (current lines) and the hunks between them.

```mermaid
flowchart TB
    sel(["selected hunks"]) --> k{"action"}
    k -- keep --> kb["base' = base with each hunk's<br/>a-range replaced by its b-lines"]
    kb --> kw["B := merge3(base, B, base')<br/>(transfers only that delta to B)"]
    kw --> kf["file untouched"]
    k -- undo --> uc["cur' = cur with each hunk's<br/>b-range replaced by its a-lines"]
    uc --> ub["put cur' into the buffer<br/>(one undo block, journal recorded)"]
    ub --> uw{"buffer had unsaved<br/>edits of yours?"}
    uw -- no --> save[":update → processed as your write"]
    uw -- yes --> unsaved["left unsaved with your edits"]
```

Keep transfers the change through `merge3` so that, in a buffer with unsaved
edits, only the kept hunk reaches B and none of your unsaved typing does.

## Partial keep and undo

With a line range (visual mode, or `:10,12Agentdiff keep`), only the
selected part of each hunk is used. A hunk's removed lines count as selected
when the range covers the hunk's first row:

```
baseline       current            selection: lines 10–11
  l9             l9
                 n10   ← added    ✓ selected
                 n11   ← added    ✓ selected
                 n12   ← added
                 n13   ← added

keep (partial):  base' = l9 n10 n11          → n12, n13 still pending
undo (partial):  cur'  = l9 n12 n13          → n12, n13 still pending
```

```mermaid
flowchart LR
    hunk["hunk: removed R, added N₁…Nₖ"] --> s{"range covers<br/>the first row?"}
    s -- yes --> sd["removed lines selected"]
    s -- no --> sn["removed lines stay pending"]
    hunk --> sl["added lines inside the range selected"]
    sd & sn & sl --> kp["keep: base gets (R unless selected) + selected N"]
    sd & sn & sl --> up["undo: cur gets (R if selected) + unselected N"]
```

## Created, deleted and binary files

| File | Keep | Undo |
|---|---|---|
| created by the agent | B := its content | delete it, wipe its buffer (windows keep a buffer) |
| deleted by the agent | B := absent | write B's content back |
| binary or over `max_file_size` | B := disk | write B's bytes back |
| renamed | a deletion plus a creation | |

## Panel, side-by-side view, statusline, file tree

The panel (tree view; `t` switches to the list):

```
 󰚩 Agent changes         5 files  +5 −2

  docs                            −1
     gone.md                    −1  D
  lua/agentdiff                +4 −1
    ui                         +2 −1
       icons.lua                +2  A
       panel.lua                −1  M
     init.lua                   +2  M
   README.md                    +1  M

 ? keys
```

It is drawn from rows (`ui/panel.rows`): text with highlight ranges, plus
right-aligned virtual text for counts and status, so nothing shifts with the
window width. Folders are compacted while they hold a single folder, and
collapsed folders are remembered for the session.

```mermaid
flowchart LR
    key(["<CR> / o on a file"]) --> ed{"current window<br/>an editing window?"}
    ed -- yes --> open["open the file there"]
    ed -- "no (panel, baseline, tree)" --> prev{"previous window<br/>editing?"}
    prev -- yes --> open
    prev -- no --> any{"another editing<br/>window in the tab?"}
    any -- yes --> open
    any -- no --> split["new split beside the panel"] --> open
```

The panel window is pinned to its buffer (`winfixbuf`), so nothing else can
take it over; `next`/`prev` from the panel use the same window choice.

```mermaid
flowchart LR
    ev(["User AgentdiffChanged"]) --> p["panel re-renders"]
    ev --> sl["statusline: status()<br/>'3 files · 6 changes'"]
    ev --> nt["file tree re-renders<br/>path_status(node.path)"]
    ev --> sbs["side-by-side baseline<br/>window updates"]
```

- **Side-by-side** (`<leader>rv`): a read-only scratch buffer with the
  baseline in a vertical split, both windows in diff mode; the inline overlay
  is hidden for that buffer meanwhile. Keep and undo work from either window
  (from the baseline window, the change is found by its baseline range).
- **File tree**: `path_status(path)` returns `"file"`, `"dir"` or `nil` from
  sets rebuilt only when the pending signature changes, so a tree can call it
  for every line it draws.
