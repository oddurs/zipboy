---
id: 50
uid: e666ec8b-8617-4136-a5ea-9af10b471a3a
title: Re-read names in a legacy encoding
type: feature
status: backlog
milestone: later
created: 2026-10-20
updated: 2026-11-01
priority: p3
effort: s
area: archive
---

## Problem

ZIPs made on old Japanese or Russian Windows show garbled names, because they are neither UTF-8 nor CP437.

## Proposal

A View > Text Encoding menu that re-decodes names, as Archive Utility can't.

## Acceptance criteria

- [ ] Choosing Shift-JIS on a Shift-JIS fixture shows the right names

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. View > Text Encoding re-reads names in a chosen encoding, and detectsAndDecodesLegacyFilenameEncodings covers decoding. The criterion's menu path on a Shift-JIS fixture is not tested. Re-reading discarded unsaved edits (0070 asks first), and a chosen encoding overrode the UTF-8 flag (0071).

## 2026-11-01

Updated after 0068-0071 merged (#25, #26, #28, #30). Flagged UTF-8 names now stay UTF-8 under a chosen encoding (keepsFlaggedNamesUTF8UnderAChosenEncoding), and re-reading asks before discarding edits (reReadingNamesWithUnsavedEditsAsksFirst). The criterion's Shift-JIS fixture through the menu is still untested.
