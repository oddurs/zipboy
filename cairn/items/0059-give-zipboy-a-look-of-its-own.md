---
id: 59
uid: 7512d74b-5943-48ae-aa4a-352077fca037
title: Give Zipboy a look of its own
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-10-24
updated: 2026-10-24
closed_at: 2026-10-24
priority: p1
effort: l
area: shell
---

## Problem

Zipboy looks like a Finder list with a different title. The empty state sits on alternating stripes that
belong to rows that aren't there, the loading state is a stock progress bar, selection is the system's
blue, and nothing ties the window to the warm, zippered icon.

## Proposal

One idea throughout: warm, a little playful, tactile, from the icon's orange and its zipper.

- A brand orange, adjusted for dark mode, used for selection, drop targets, and the empty and loading states.
- The list without stripes, rows a little taller, selection as a soft tinted capsule inset from the edges,
  joined across neighbouring rows, with the text kept dark so it stays readable.
- An empty state that is a drop tray: dashed rounded outline, the zipper glyph, a Choose Files… link, and
  while something is dragged over it, an orange glow and marching dashes. The column header hides while
  there is nothing to sort.
- Unpacking shown as a zipper closing tooth by tooth.
- Drop targets glowing orange, on a folder row or around the whole list.
- The inspector's preview as a rounded card with a shadow; headings in SF Rounded; small uppercase keys.
- Animations off under Reduce Motion.

## Acceptance criteria

- [x] Screenshots of the empty, loading, browsing, and inspector states in light and dark show the new look
- [x] The drop tray's highlighted state is checked by rendering it, without driving the mouse
- [x] Selected text has at least 4.5:1 contrast against the selection in both appearances
- [x] With Reduce Motion on, nothing animates
- [ ] VoiceOver still reads the empty state, the Choose Files… link, and the loading progress

## 2026-10-24

Evidence: screenshots of the empty, loading, browsing, multi-selection and inspector states in light and dark (README's docs/screenshots retaken with the new look). The highlighted drop tray was rendered from an off-screen window in a throwaway test, not by driving the mouse: orange dashed edge and tinted fill in both appearances. Contrast, measured with the system's own label and list colours composited with the tint: name text 13.1:1 light, 7.5:1 dark; secondary text measured 3.8:1 and 4.2:1 on the tint, so selected rows now use the primary colour for it (LookTests.selectedRowsKeepTheirTextReadable). Reduce Motion: LookTests.traysMarchOnlyWhenMotionIsAllowed injects the setting and checks the marching animation appears only when motion is allowed; the Mac's own setting was not changed. VoiceOver: LookTests.voiceOverHearsEachState checks the group label for each state, the Choose Files… label, and the zipper's progress role and '42 percent' value; VoiceOver itself was not run, so criterion 5 stays open.

## Result

Zipboy has its own look: orange tint, rounded type, a drop tray, a zipper for unpacking.
