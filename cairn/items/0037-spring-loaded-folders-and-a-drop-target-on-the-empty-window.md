---
id: 37
uid: f8ff130c-0f9c-4541-93ff-ec3a1a7b94fe
title: Spring-loaded folders and a drop target on the empty window
type: feature
status: done
milestone: v0.4
created: 2026-10-20
updated: 2026-11-01
closed_at: 2026-11-01
priority: p2
effort: s
area: browser
---

## Problem

Dropping deep into an archive means expanding folders first, and dragging onto an empty window gives little feedback.

## Proposal

Expand folders after a short hover while dragging, as Finder does, and highlight the empty-state view as a drop target.

## Acceptance criteria

- [x] Hovering a dragged item over a collapsed folder for 0.7 s expands it
- [x] The empty window's message highlights while a drag is over it

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Criterion 1: springLoadingExpandsCollapsedFolderAfterHover. Criterion 2: the empty window's drop tray has highlighted since 0059 (EmptyStateView.highlighted, traysMarchOnlyWhenMotionIsAllowed).
