---
id: 21
uid: a92944b2-ee2e-4954-9a8e-1c75c37fcf5d
title: Save through ZipWriter so small changes to big archives save in seconds
type: feature
status: backlog
milestone: v0.2
depends_on:
- 19
- 20
created: 2026-10-20
updated: 2026-11-01
priority: p0
effort: m
area: document
---

## Problem

Even with the writer and the tracking in place, saving still goes through libarchive.

## Proposal

When the document came from a ZIP, the save hands ZipWriter the tracked entries; archives made new or imported from other formats keep using the full write.

## Acceptance criteria

- [ ] Changing one file in a 2 GB ZIP saves in under 3 seconds on an M1
- [x] Unchanged entries in the saved file are byte-identical to the original's
- [x] Autosave cancellation still works mid-write
- [ ] Falls back to the full write, with a log line, when the source changed on disk since opening

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Saves go through ZipWriter when there is no password. Criterion 2: deltaSavePreservesUnchangedEntriesByteForByteAcrossEdits. Criterion 3: anEditCancelsAnAutosaveAndLeavesTheFileAlone and anEditDuringASaveWaitsForTheNextOne still pass. Open: criterion 1 (no 2 GB measurement), criterion 4 (no fallback-with-log path found for a source changed on disk).
