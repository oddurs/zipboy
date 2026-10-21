---
id: 11
uid: 96edd85a-c9ce-4fa8-b151-d87e83bf91e8
title: Launching a second Zipboy deletes the first one's open archives
type: bug
status: backlog
milestone: v0.1
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: s
area: document
---

## What happens

At launch, `Workspace.removeAbandoned()` deletes everything under `$TMPDIR/Zipboy`, including the workspaces of another running instance. Its open documents lose their files mid-edit.

## What should happen

Only workspaces whose owning process has exited are removed. Each workspace records its owner's pid; the sweep skips any whose pid is alive.

## Reproduction

1. Open an archive in Zipboy.
2. Run `open -n /Applications/Zipboy.app`.
3. Preview a file in the first window: it is gone.
