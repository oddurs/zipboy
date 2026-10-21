---
id: 20
uid: 8a846293-f908-4a05-82c6-73d9bd6df4c7
title: Know which workspace files still match their archive entry
type: feature
status: backlog
milestone: v0.2
depends_on:
- 18
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: document
---

## Problem

To copy an entry verbatim, the save must know the file in the workspace is untouched: not edited in place, not replaced, not renamed.

## Proposal

At unpack, record each file's catalog entry, inode, size, and modification time. A file is unchanged if all three still match; a rename keeps the entry but changes the stored name.

## Acceptance criteria

- [ ] An untouched file maps to its original entry
- [ ] A file saved over by another app counts as changed
- [ ] A renamed or moved file keeps its data but writes a new name
- [ ] Undo and redo keep the mapping right, covered by document tests
