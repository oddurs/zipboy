---
id: 37
uid: f8ff130c-0f9c-4541-93ff-ec3a1a7b94fe
title: Spring-loaded folders and a drop target on the empty window
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
priority: p2
effort: s
area: browser
---

## Problem

Dropping deep into an archive means expanding folders first, and dragging onto an empty window gives little feedback.

## Proposal

Expand folders after a short hover while dragging, as Finder does, and highlight the empty-state view as a drop target.

## Acceptance criteria

- [ ] Hovering a dragged item over a collapsed folder for 0.7 s expands it
- [ ] The empty window's message highlights while a drag is over it
