---
id: 20
uid: 8a846293-f908-4a05-82c6-73d9bd6df4c7
title: Know which workspace files still match their archive entry
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
depends_on:
- 18
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: m
area: document
---

## Problem

To copy an entry verbatim, the save must know the file in the workspace is untouched: not edited in place, not replaced, not renamed.

## Proposal

At unpack, record each file's catalog entry, inode, size, and modification time. A file is unchanged if all three still match; a rename keeps the entry but changes the stored name.

## Acceptance criteria

- [x] An untouched file maps to its original entry
- [x] A file saved over by another app counts as changed
- [x] A renamed or moved file keeps its data but writes a new name
- [x] Undo and redo keep the mapping right, covered by document tests

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Workspace files are matched to entries by inode, size and mtime (ArchiveDocument.refreshTrackingAfterSave). Criterion 1 holds per deltaSavePreservesUnchangedEntriesByteForByteAcrossEdits. Criterion 2 failed for a file replaced during a save (data loss), fixed in 0068 (PR #25). Criteria 3 and 4 have no test.

## 2026-11-01

Updated after 0068-0071 merged (#25, #26, #28, #30). Criterion 2: aFileReplacedDuringASaveReachesTheNextOne.

## 2026-11-07

Switched FileIdentity and SourceSignature to Darwin.lstat with exact nanosecond st_mtimespec matching (catching sub-millisecond same-size in-place overwrites while preserving identity across rename(2) moves and Holding-area undo/redo). Added SaveTests.renamedAndMovedFilesKeepCompressedPayloadAndUndoRedoTracksEntries covering file/folder rename and move payload reuse plus undo/redo across rename, move, delete, and replace.

## Result

Workspace files track catalog entries by inode, size, and nanosecond mtime across renames, moves, and undo/redo, covered by SaveTests.
