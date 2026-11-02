---
id: 35
uid: 0721bb86-d9c6-4a8f-94d2-83dfbb357aa2
title: VoiceOver and full keyboard access across every flow
type: feature
status: planned
milestone: v0.4
created: 2026-10-20
updated: 2026-11-02
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
- [x] Every control has an accessibility label; rows read name, kind, and size
- [x] Adds, deletes, and saves are announced
- [ ] The Accessibility Inspector audit reports no issues

## 2026-11-02

2026-11-02. AccessibilityTests walks every visible control and image-role view in the empty archive window, an archive with a file selected, About, Welcome, and Settings, and requires a name; pop-ups and segmented controls need a label of their own, since their titles are the current choice. It found the four Settings choices unnamed (their labels are separate grid cells) and Mugi uncounted; both fixed. It also refuses to pass when it finds nothing, which it did at first, because NSButton's own isAccessibilityElement is false. Rows: name, size, and kind cells checked. Adds, deletes, and explicit saves (not autosaves) post VoiceOver announcements through Announcer. Criteria 1 and 4 stay open: docs/accessibility.md is the hand checklist, not yet run with VoiceOver, and the Accessibility Inspector needs Xcode.
