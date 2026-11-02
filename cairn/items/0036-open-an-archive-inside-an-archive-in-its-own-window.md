---
id: 36
uid: 52da07fe-8f5c-4ecd-a43f-ed84ff6ab388
title: Open an archive inside an archive in its own window
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-11-01
priority: p2
effort: l
area: document
---

## Problem

Double-clicking a ZIP inside a ZIP hands it to whatever app owns ZIPs, and changes to it are lost.

## Proposal

Open nested archives as child documents. Saving the child writes it back into the parent's workspace, and the parent counts as changed.

## Acceptance criteria

- [ ] Double-clicking an inner archive opens it in Zipboy with a title showing both names
- [x] Changes saved in the child appear in the parent, which then autosaves
- [x] Closing the parent first asks about, or saves, the child

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Nested archives open in their own document with the parent tracked. Criterion 2: nestedArchiveTracksParentAndFinderServicesRoundTrip. Criterion 3: closing the parent deleted the workspace under an open child; 0070 (PR #26) makes the child close and save first. Criterion 1 (title with both names) not verified.

## 2026-11-01

Updated after 0068-0071 merged (#25, #26, #28, #30). Criterion 3: closingAParentSavesTheNestedArchiveOpenFromItFirst.
