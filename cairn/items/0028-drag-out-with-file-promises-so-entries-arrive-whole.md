---
id: 28
uid: 34262365-04c7-4583-955c-ba7d1aa51bc2
title: Drag out with file promises so entries arrive whole
type: feature
status: backlog
milestone: v0.3
depends_on:
- 27
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: m
area: browser
---

## Problem

Dragging an entry that isn't unpacked has no file URL to hand to Finder.

## Proposal

Provide `NSFilePromiseProvider` items; write each entry to the destination Finder chooses when the drop lands. Unpacked entries keep using their file URL.

## Acceptance criteria

- [ ] Dragging a not-yet-unpacked file or folder to Finder produces the complete item
- [ ] Dragging to Mail and Messages attaches the file
- [ ] A 2 GB entry dragged out shows Finder's own progress
