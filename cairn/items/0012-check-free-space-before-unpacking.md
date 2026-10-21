---
id: 12
uid: 432cb06f-e9f5-408b-be24-eb66d7ae4a7c
title: Check free space before unpacking
type: feature
status: backlog
milestone: v0.1
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: s
area: document
---

## Problem

Opening unpacks the whole archive into the temporary folder. On a nearly full disk it fails partway with a raw POSIX error and leaves a half-written workspace behind.

## Proposal

Before writing each entry, compare its size with the volume's available capacity for important usage. If it won't fit, stop, remove the workspace, and say how much is needed and how much is free.

## Acceptance criteria

- [ ] Opening an archive larger than the free space shows “Not enough space to open “x.zip”. It needs about N GB; M GB is free.” and closes the window
- [ ] No partial workspace is left in `$TMPDIR/Zipboy`
- [ ] Covered by a kit test that injects a small capacity
