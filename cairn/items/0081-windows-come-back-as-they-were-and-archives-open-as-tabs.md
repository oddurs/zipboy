---
id: 81
uid: b84ae764-e1c9-4859-bf26-697b7e80d07b
title: Windows come back as they were, and archives open as tabs
type: feature
status: backlog
milestone: v0.4
created: 2026-11-02
updated: 2026-11-02
priority: p2
effort: s
area: shell
---

## Problem

Nobody has checked what a relaunch restores beyond the window frame: which folders were open,
what was selected, and whether the inspector was shown. Window tabs (Window > Merge All Windows,
dragging a tab out) have not been tried either.

## Proposal

Encode the expanded folder paths, the selection, the search text, and the inspector's state in
`ArchiveWindowController.encodeRestorableState(with:)` and restore them once the archive has
loaded. Keep `tabbingMode` automatic, so tabs follow the person's "Prefer tabs" setting and each
tab reads as the archive's name.

## Acceptance criteria

- [ ] Encoding then restoring a window's state reopens the same folders and selects the same items, covered by a test
- [ ] Restoring state that names paths no longer in the archive is ignored, not an error
- [ ] Window > Merge All Windows puts two archives in one window as tabs, checked on screen
