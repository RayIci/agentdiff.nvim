# Detection

How agentdiff notices disk changes, how fast, and how it avoids blaming the
agent for writes that aren't its own.

- [The poll loop](#the-poll-loop)
- [Timing](#timing)
- [The settle period](#the-settle-period)
- [Shell commands run from Neovim](#shell-commands-run-from-neovim)
- [Several Neovim instances on one project](#several-neovim-instances-on-one-project)
- [Startup and restarts](#startup-and-restarts)
- [Cost](#cost)

## The poll loop

There are no file watchers: libuv's `fs_event` isn't recursive on Linux, and a
watcher per directory doesn't scale. Instead, while Neovim is focused, a timer
runs two git queries against the **observed** index:

```
git diff --name-status -z --no-renames        # tracked files whose content differs from O
git ls-files -o --exclude-standard -z          # files O doesn't have (new, not ignored)
```

Both compare stat data first, so an unchanged tree costs a few milliseconds.

```mermaid
stateDiagram-v2
    [*] --> Polling
    Polling --> Paused: FocusLost
    Paused --> Polling: FocusGained (poll at once)
    Polling --> Polling: every poll_interval (1 s)
    Polling --> Confirming: unclaimed change seen
    Confirming --> Polling: confirmed after settle (300 ms)<br/>or claimed meanwhile
```

Extra polls also run on `BufEnter` (throttled to 200 ms) and synchronously
around shell commands. With tmux `focus-events on`, switching to the Neovim
pane gains focus and polls immediately.

## Timing

Worst case from the agent's write to the overlay, while Neovim is focused:

```mermaid
gantt
    dateFormat X
    axisFormat %L ms
    title Agent write → pending change (worst case, focused)
    section Agent
    write lands just after a poll    :milestone, 0, 0
    section agentdiff
    wait for the next poll           :a1, 0, 1000
    poll sees D ≠ O (suspect)        :a2, 1000, 1030
    settle period                    :a3, 1030, 1330
    confirmation poll, process       :a4, 1330, 1380
    refresh + draw                   :a5, 1380, 1420
    section Requirement
    detected within 2 s              :crit, 0, 2000
```

| Situation | When the change shows |
|---|---|
| Neovim focused | ≤ ~1.4 s (spec: ≤ 2 s) |
| Neovim unfocused | on focus gain (the timer is paused) |
| Neovim not running | at the next start, from the persisted store |
| a buffer showing the file | the buffer reloads (or merges) right after processing |

## The settle period

A newly seen, unclaimed change isn't blamed on the agent at once. It becomes
a *suspect*, and a confirmation poll `settle` ms later decides. That window
lets claims from other places arrive first:

```mermaid
sequenceDiagram
    autonumber
    participant N2 as Neovim #2
    participant FS as Disk
    participant C as claims/ (shared)
    participant N1 as Neovim #1 (detect)
    N2->>C: BufWritePre: claim foo.lua
    N2->>FS: write foo.lua
    N1->>FS: poll: foo.lua D ≠ O
    N1->>C: claimed? yes → yours
    Note over N1: without the claim yet visible,<br/>foo.lua would wait 300 ms as a suspect
    N2->>N2: BufWritePost: process as user (shared B and O)
```

Short-lived files (a formatter's temp copy, an editor's swap file outside the
excludes) usually disappear inside the settle period and are never reported.

## Shell commands run from Neovim

```mermaid
sequenceDiagram
    autonumber
    participant U as You
    participant D as detect
    participant Sh as shell
    U->>D: CmdlineLeave ":silent !sed -i … foo.lua"
    D->>D: recognise a shell command (modifiers stripped)
    D->>D: settle pending changes as the agent's now
    U->>Sh: run
    Sh->>Sh: edits foo.lua
    Sh-->>D: ShellCmdPost
    D->>D: every change found now is yours
```

Recognised: `:!cmd`, `:{range}!filter`, `:r !cmd`, `:w !cmd`, behind any of
`:silent`, `:keepalt`, `:verbose`, `:noautocmd`, … (`:w!`, a forced write, is
not a shell command).

## Several Neovim instances on one project

All instances share one store, so the baseline is the same everywhere:

```mermaid
flowchart LR
    n1["Neovim #1"] & n2["Neovim #2"] --> lock{"lock/<br/>(mkdir mutex)"}
    lock --> B[("baseline.idx")] & O[("observed.idx")]
    n1 & n2 <--> C[("claims/")]
```

- Writes by either instance are claimed in `claims/` and processed under the
  store lock; processing is idempotent (`merge3(D, B, D) == B`), so it
  doesn't matter which instance gets there first.
- git's own `index.lock` serializes index writes; agentdiff retries with
  back-off.

## Startup and restarts

```mermaid
flowchart TB
    s(["VimEnter"]) --> on{"enabled?"}
    on -- no --> off["nothing"]
    on -- yes --> root["root = git toplevel or cwd"]
    root --> home{"~ or / ?"}
    home -- yes --> off
    home -- no --> ep{"store epoch ==<br/>global epoch?"}
    ep -- no --> rebuild["drop the store<br/>(it predates a disabled period)"]
    ep -- yes --> ready{"baseline exists?"}
    rebuild --> snap
    ready -- no --> snap["background snapshot<br/>(ls-files → update-index)"]
    snap --> big{"> max_files?"}
    big -- yes --> notice["notice, not reviewed"]
    big -- no --> active
    ready -- yes --> clean["drop .git/ and ignored entries"]
    clean --> active(["active: first refresh, then poll"])
```

Because B and O persist, an agent that worked while Neovim was closed is
noticed at the next start: those files simply have `D ≠ O`.

## Cost

| Operation | Typical cost |
|---|---|
| poll on an unchanged tree | 2 git processes, stat-only |
| an unprocessed change | `cat-file --batch` reads + one `update-index` |
| a discard check | one read-only `cat-file --batch` on the project (`HEAD:path`) |
| your `:w` | 1 read + 1 write of the store indexes, synchronous |
| first snapshot | proportional to project size, in the background |
| a buffer's overlay | one in-memory `vim.text.diff` per change, debounced 100 ms |
