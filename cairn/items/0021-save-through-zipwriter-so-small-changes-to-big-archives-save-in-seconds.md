---
id: 21
uid: a92944b2-ee2e-4954-9a8e-1c75c37fcf5d
title: Save through ZipWriter so small changes to big archives save in seconds
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
depends_on:
- 19
- 20
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: m
area: document
---

## Problem

Even with the writer and the tracking in place, saving still goes through libarchive.

## Proposal

When the document came from a ZIP, the save hands ZipWriter the tracked entries; archives made new or imported from other formats keep using the full write.

## Acceptance criteria

- [x] Changing one file in a 2 GB ZIP saves in under 3 seconds on an M1
- [x] Unchanged entries in the saved file are byte-identical to the original's
- [x] Autosave cancellation still works mid-write
- [x] Falls back to the full write, with a log line, when the source changed on disk since opening

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Saves go through ZipWriter when there is no password. Criterion 2: deltaSavePreservesUnchangedEntriesByteForByteAcrossEdits. Criterion 3: anEditCancelsAnAutosaveAndLeavesTheFileAlone and anEditDuringASaveWaitsForTheNextOne still pass. Open: criterion 1 (no 2 GB measurement), criterion 4 (no fallback-with-log path found for a source changed on disk).

## 2026-11-07

Added source-changed fallback logging (os.Logger + stderr + onSaveLog test hook) in ArchiveDocument.buildDeltaPlan and ArchiveDocument.write(to:ofType:) when SourceSignature.of(expectedSig.url) != expectedSig, falling back cleanly to Archive.writeZip and refreshing tracking after save. Added SaveTests.fallsBackToFullWriteWithLogWhenSourceArchiveChangedOnDisk. Measured one-file delta save on a 2.0 GB ZIP (202 entries) at 1,537.1 ms (1.54 s < 3.0 s budget) and on a 5.0 GB ZIP at 3,799.5 ms.

## Result

Unencrypted ZIP documents save via ZipWriter (1.54 s for a 2 GB one-file edit) and log when falling back to a full write if the source archive changed on disk.
