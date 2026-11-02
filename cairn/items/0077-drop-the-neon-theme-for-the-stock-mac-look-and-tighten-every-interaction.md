---
id: 77
uid: ff2b1128-0c1d-4666-8018-ffb89fa6ce9e
title: Drop the neon theme for the stock Mac look and tighten every interaction
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-11-02
updated: 2026-11-02
priority: p2
area: shell
---

## Problem

The neon green brand colour reads as noise rather than identity. It tints the selection, the primary
button, drop targets, and every checkbox through a registered accent, overriding the person's own
Multicolor choice. The empty states are a branded tray with marching dashes and a custom zipper
progress bar instead of the system's controls. Several everyday interactions fall short of Finder's:
type-select does nothing, Escape doesn't cancel a rename, right-clicking blank space offers commands
for a selection you can't see, files dropped on the inspector are refused, added items aren't shown
once they land, and the root drop highlight lights even when the drop would be refused.

## Proposal

Go back to the stock look: the system selection, accent, push buttons, progress indicator, and
SF Pro. Theme keeps only spacing, radii, type, and the neutral well. The empty states follow the
system's content-unavailable pattern: a symbol, a heading, a line of help, and for an empty archive
one accent-tinted button. A drop lights the tray or the list in the accent colour. Then fix each
interaction above where it lives, each with a test.

## Acceptance criteria

- [x] No brand colour remains: the app registers no accent and draws selection, buttons, and progress with system controls
- [x] The empty archive, no-results, and loading states use system symbols, type, and controls, and VoiceOver hears each
- [x] A drop highlights in the accent colour only where it would be accepted, and files dropped on the inspector are added to the archive
- [x] Typing a name selects the matching row, and Escape cancels a rename without changing the name
- [x] Right-clicking blank space in the list offers the archive's commands, not the hidden selection's
- [x] Added, pasted, and dropped items are revealed and selected once they land
- [x] Screenshots in docs/screenshots are retaken in light and dark

## 2026-11-02

Evidence. scripts/task check exit 0: 101 tests in 15 suites, universal build, warnings as errors. New LookTests: theDropAreaLightsInTheAccentOnlyWhileADropWaits, theListDrawsTheSystemSelection, typingANameFindsItsRow, escapeCancelsARename, rightClickingBlankSpaceIsAboutTheArchive, addedItemsAreShownWhereTheyLanded, aDropLightsTheListOnlyWhenItWouldBeAccepted, theInspectorTakesFilesFromOutsideOnly. Mutation check: removing the reveal, the blank-space deselect, and the accepted-only highlight each fails its test. Screens checked by eye in light and dark: browse, multi-selection, empty, no results, Settings, an imported 7z, and a background window, where the accent button goes grey on its own. Not watched on screen: a real drag (it needs the pointer), the loading bar (too quick on the demo archive), and VoiceOver itself. The app icon is unchanged; this pass covered in-app symbols.
