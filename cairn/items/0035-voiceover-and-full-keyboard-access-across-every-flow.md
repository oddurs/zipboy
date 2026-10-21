---
id: 35
uid: 0721bb86-d9c6-4a8f-94d2-83dfbb357aa2
title: VoiceOver and full keyboard access across every flow
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: quality
---

## Problem

Nobody has used Zipboy with VoiceOver. Toolbar items, rows, the inspector, and the empty state may read badly or not at all.

## Proposal

An audit with VoiceOver and Full Keyboard Access over every README flow, fixing labels, roles, focus order, and announcements for changes such as “3 items added”.

## Acceptance criteria

- [ ] Every README flow can be completed with VoiceOver and the keyboard only, written up as a checklist in `docs/`
- [ ] Every control has an accessibility label; rows read name, kind, and size
- [ ] Adds, deletes, and saves are announced
- [ ] The Accessibility Inspector audit reports no issues
