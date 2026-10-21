---
id: 11
uid: 96edd85a-c9ce-4fa8-b151-d87e83bf91e8
title: Launching a second Zipboy deletes the first one's open archives
type: bug
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-10-20
closed_at: 2026-10-20
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

## 2026-10-20

Fixed: each workspace writes its owner's pid to Owner; the launch sweep removes only workspaces whose owner has exited, has no Owner file, or names a non-positive pid. WorkspaceTests.sweepKeepsWorkspacesOfRunningProcesses failed on the old sweep (the running process's workspace was deleted) and passes now.

## Result

Launch sweep keeps workspaces of running processes.
