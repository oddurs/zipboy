---
id: 36
uid: 52da07fe-8f5c-4ecd-a43f-ed84ff6ab388
title: Open an archive inside an archive in its own window
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
priority: p2
effort: l
area: document
---

## Problem

Double-clicking a ZIP inside a ZIP hands it to whatever app owns ZIPs, and changes to it are lost.

## Proposal

Open nested archives as child documents. Saving the child writes it back into the parent's workspace, and the parent counts as changed.

## Acceptance criteria

- [ ] Double-clicking an inner archive opens it in Zipboy with a title showing both names
- [ ] Changes saved in the child appear in the parent, which then autosaves
- [ ] Closing the parent first asks about, or saves, the child
