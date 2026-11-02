---
id: 68
uid: ac9b9336-e318-4398-8b67-f0699a97756a
title: Saving after an edit mid-save keeps the edit, and delta saves keep extra fields
type: bug
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p0
area: archive
effort: m
---

## Problem

Two ways a delta save (`ZipWriter` copying unchanged entries verbatim) writes the wrong archive:

1. **An edit made while an explicit save is writing is lost on the next save.** After a save,
   `ArchiveDocument.refreshTrackingAfterSave` re-reads the saved catalog and links each entry to the
   workspace file that is there *now*. A file replaced while the save was writing gets linked to an
   entry holding its old bytes. The next save sees a matching inode, size, and modification date, and
   copies the old bytes verbatim. The edit never reaches disk, and nothing says so.
2. **Delta saves drop every central-directory extra field.** `ZipWriter`'s central record has no
   extra field, so a verbatim entry loses its 0x7075 Unicode Path, extended timestamps (0x5455),
   and Unix uid/gid (0x7875). An entry named through 0x7075 changes name on the first save:
   `["Ã©té.txt"]` before, `["âté.txt"]` after.

## Proposal

1. Take each workspace file's identity (inode, size, modification date) on the main thread *before*
   the save's snapshot is cloned, and after the save link catalog entries to those identities rather
   than to the workspace as it stands. A file changed during the save then no longer matches its
   entry, so the next save compresses it afresh. Taking the identities before the clone means an
   outside change racing the clone can only cause an extra recompression, never stale bytes.
2. Carry each verbatim entry's central extra field through `ZipWriter`, minus its Zip64 field, which
   the writer rebuilds for the entry's new offset. A renamed entry also drops 0x7075, which names the
   old path and would override the new one in readers that honour it. A rewritten local header
   (renamed, or one that had a data descriptor) keeps its local extra field on the same terms.

## Acceptance criteria

- [x] A `SaveTests` case replaces a file while an explicit save writes, saves again, and the archive holds the new bytes; it fails on `main`
- [x] A `ZipboyKit` test delta-saves an entry named by 0x7075 and its name reads the same afterwards; it fails on `main`
- [x] Extended-timestamp and uid/gid extra fields survive a verbatim copy and a rename, and a renamed entry loses its stale 0x7075 field
- [x] An entry whose new offset passes 4 GiB gets a correct Zip64 extra field beside its carried fields (tested on the central-header builder)
- [x] `scripts/task check` passes

## 2026-11-01

Regression test for the mid-save edit, run against the unfixed code: `scripts/task test aFileReplacedDuringASaveReachesTheNextOne` printed "Expectation failed: (saved → "old") == "new content"". The replacement made while the first save wrote was linked to the entry holding "old", and the second save copied it verbatim.

## 2026-11-01

Regression test for extra fields, run against the unfixed code: `scripts/task test deltaSavesKeepExtraFields` printed "(copy.path → "ete.txt") == "été.txt"", "(copy.extraField → 0 bytes) == (entry.extraField → 42 bytes)", "(moved.extraField → 0 bytes) == (timestamp + owner → 24 bytes)", and a failed comparison of the renamed entry's local extra field. Every central extra field was dropped, so the 0x7075 name fell back to the raw one.

## 2026-11-01

After the fix both regression tests pass: "✔ Test aFileReplacedDuringASaveReachesTheNextOne() passed" and "✔ Test deltaSavesKeepExtraFields() passed". `scripts/task check` exits 0 with 70 tests in 13 suites passing and the universal build assembled.

## 2026-11-01

Identities are taken before the clone, not after, on purpose: an outside app changing a file between the stat and the clone can then only cost a recompression on the next save, never stale bytes. The delta plan still checks live files after the clone, which is the safe order for deciding what this save copies. Cost: one extra walk and stat of the workspace on the main thread per unencrypted save.

## 2026-11-01

Zip64 central fields are stripped from carried extras and rebuilt by `ZipWriter.centralHeader` for the new offset. If carried fields plus a new Zip64 field would pass the 16-bit length, Zip64 wins and the carried fields are dropped; no test reaches that case.

## Result

A save now links its entries to each workspace file as it was just before the snapshot was cloned, so a file changed while the save writes is compressed afresh next time instead of being replaced by its old bytes. ZipWriter carries every central and local extra field of a verbatim entry, rebuilding Zip64 for the new offset and dropping 0x7075 only when the entry is renamed. Regression tests: SaveTests.aFileReplacedDuringASaveReachesTheNextOne, ArchiveTests.deltaSavesKeepExtraFields, ArchiveTests.rewrittenHeadersRebuildZip64BesideCarriedFields.
