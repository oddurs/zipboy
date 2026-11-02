---
id: 76
uid: 150b2675-8fd8-433f-a5b0-b17bf833bf67
title: Polish every surface of the app until nothing looks unconsidered
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p2
area: shell
---

## Problem

After the design-system pass the app looked right in a still screenshot but not in use. The prominent
button stayed neon in a background window while the rest of the window went grey. View > Show
Preview never changed to say Hide when the inspector was open. The inspector heading repeated what the
title bar and its own table already said: the item count, the size, and the format. The empty tray's
only action was a plain grey button. The context menu had no symbols while the menu bar did. Clearing
a search collapsed every folder that had been open before it. The list also made a new date formatter
for every cell it drew.

## Proposal

Fix each of those where it lives. The prominent button follows its window's main state, as the
system default button does. A split view controller subclass names the inspector toggle Show
Inspector or Hide Inspector. The heading gives the kind, and the table gives the facts. The tray's
Choose Files becomes the window's one prominent action, which is possible because the inspector hides
its footer for an empty archive. The context menu borrows the menu bar's symbols. The list keeps
which folders were open when a search begins and puts them back when it ends, revealing the
selection. One shared formatter serves every row.

## Acceptance criteria

- [x] The prominent button goes quiet while its window is in the background (`LookTests`)
- [x] The View menu reads Hide Inspector while the inspector is open and Show Inspector while it is not
- [x] The inspector heading names the kind and repeats nothing the table or title bar says
- [x] An empty archive's tray offers Choose Files as the window's one prominent action
- [x] Every context-menu command carries the symbol the menu bar uses for it
- [x] Ending a search reopens the folders that were open before it, with the selection kept and revealed
- [x] The README screenshots show the current app in light and dark mode

## Result

Seven fixes across the window: background-aware prominent button, Show/Hide Inspector, a heading that repeats nothing, a prominent Choose Files, symbols in the context menu, search that restores open folders, one shared date formatter. Each has a LookTests case; screenshots retaken.
