---
id: 67
uid: 26825f33-2e7f-4924-94d7-7fcaaaad0890
title: A neon design system on a native Mac window
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p1
effort: l
area: shell
---

## Problem

The 2026-11-01 batch of changes (0063, 0064) replaced the look from 0059 with stock system colours
and rebuilt the inspector without a system behind it. The result reads unfinished: the information
table is right-aligned with ragged labels and dividers that start at different points, the preview
well is invisible, the title doesn't line up with the table, the action strip is a row of 10-point
captions, stripes run down an empty list, and the Kind column truncates in the middle of a word.
Nothing ties the window to a brand colour, and the contrast test from 0059 was deleted.

## Proposal

A small design system in `Sources/Zipboy/Theme.swift`, with neon green as the one brand colour and
everything else native:

- Tokens: a neon palette tuned per appearance (a bright fill, a deeper stroke and text green for light
  mode, dark ink for text on the fill), a 4-point spacing scale, three radii with continuous corners,
  a type ramp, and motion that respects Reduce Motion.
- Native controls follow the brand: the app sets the system green as its accent only while the person
  uses Multicolor, the rule Apple applies to app accent colours, so checkboxes, switches, focus rings,
  and default buttons match without custom drawing.
- The list: no stripes, selection as a neon-tinted capsule joined across neighbouring rows with text
  kept readable, neon drop targets, tail truncation for kinds and dates.
- The inspector: a visible preview well, the title aligned with a full-width information table, a
  scrolling body, and a footer with one prominent action and one secondary, instead of four captions.
- The empty tray, zipper progress, and Settings and Help windows on the same tokens.
- A path rule so new UI code uses the tokens, never raw colours or sizes.

## Acceptance criteria

- [x] Screenshots of the empty, browsing, selection, and inspector states in light and dark show the new look
- [x] Selected text has at least 4.5:1 contrast against the selection in both appearances, checked by a test
- [x] Text on the neon fill has at least 4.5:1 contrast in both appearances, checked by a test
- [x] The app accent is set only when the person hasn't chosen one, checked by a test
- [x] Every row of the information table starts and ends at the same x positions, checked by a test
- [x] With Reduce Motion on, nothing animates

## 2026-11-01

Evidence. Screenshots: browse (photo selected), empty, and imported 7z states in light and dark were retaken from a debug build into docs/screenshots; multi-selection and Settings were checked by eye in both appearances. Palette chosen by WCAG maths: neon #39FF6E dark / #2EE85F light with ink #06301A (8.9-10.9:1); accent #0B7A30 in light because raw neon is 1.6:1 on white; selection at 30% light / 22% dark keeps labels at 13.4:1 and 6.8:1. LookTests: selectedRowsKeepTheirTextReadable, inkReadsOnNeonAndTheAccentReadsOnTheWindow, theAccentFollowsOnlyWhenThePersonHasNotChosenOne, infoTableRowsShareTheirEdges, theInspectorOffersOneProminentAction; 11 of 11 pass. The ragged table on main came from NSStackView's .width alignment, which matches arranged views to each other rather than to the stack; the edge test would fail against that layout. Reduce Motion: the redesign adds no animation; the tray's march stays gated (traysMarchOnlyWhenMotionIsAllowed). The per-app accent was probed first in a throwaway AppKit program: registering AppleAccentColor=3 turns checkboxes, switches, segmented controls, default buttons and focus rings green, and controlAccentColor reads (0.38, 0.73, 0.27). Not done: VoiceOver itself was not run.

## Result

Zipboy has a design system with neon green as its one brand colour. Native controls take the green
through the app accent while the person uses Multicolor. The list selects with a joined neon capsule,
and the inspector has a visible preview well, a full-width table and one prominent action. Contrast and
layout are pinned by LookTests.
