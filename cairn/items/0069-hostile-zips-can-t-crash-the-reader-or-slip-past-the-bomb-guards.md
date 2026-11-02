---
id: 69
uid: 8230eade-80dc-48f6-8721-7c2382572dbc
title: Hostile ZIPs can't crash the reader or slip past the bomb guards
type: bug
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p0
effort: m
area: archive
---

## Problem

Three defects found in review of the 2026-11-01 batch:

1. `ZipCatalog.read` adds offsets taken from the file without overflow checks (the Zip64 locator
   offset, each entry's local header offset, and the overlap check). A Zip64 locator pointing near
   `UInt64.max` traps the process; libarchive opens the same file, so the app crashes on open.
2. The bomb guard refuses anything that expands past 1,000:1 once it passes 64 MiB. Deflate reaches
   about 1,030:1 on zeros, so a ZIP of 100 MiB of zeros (a blank disk image) is refused as a bomb.
3. The Deflate64 fallback decodes without the bomb guards: the declared size is checked only after
   the whole entry is decoded, and neither the ratio nor the running total is applied.

## Proposal

- Bound every file-supplied offset by the file size before adding to it, in `ZipCatalog` and in
  `Deflate64.locateEntry` (`cdOffset + cdSize`, `dataOffset + compSize`, and the local header
  offset), and throw `unreadable` instead of trapping.
- Replace the flat ratio with an expansion floor: nothing is refused for its ratio until the archive
  has produced 1 GB (0041's line). Past it, refuse more than 100:1 against the compressed bytes
  consumed so far, and refuse up front any declared size that the whole file could not honestly
  produce at that ratio. Free space is still checked against declared sizes.
- Route the Deflate64 decoder through the same guard on every flushed window, and stop it the
  moment it passes the entry's declared size.

## Acceptance criteria

- [x] A ZIP with a Zip64 locator offset near `UInt64.max` throws `ArchiveError.unreadable` from `ZipCatalog.read` instead of trapping, covered by a test
- [x] Entries whose local header offset or compressed size would overflow `UInt64` throw `ArchiveError.unreadable`, covered by a test
- [x] `Deflate64.locateEntry` throws `ArchiveError.unreadable` for a Zip64 directory or an entry compressed size that would overflow `UInt64`, covered by tests
- [x] A ZIP of 100 MiB of zeros extracts in full
- [x] A 10 GB single-entry ZIP bomb is refused before anything is written, and a 16-entry bomb that hides behind the archive's size stops before 1 GB is written, covered by tests
- [x] A Deflate64 entry that expands past its declared size, or past the bomb limits, stops while streaming with `suspiciousArchive`, covered by tests
- [x] `scripts/task check` passes

## 2026-11-01

Before the fix (HostileZipTests, each run alone with scripts/task test): catalogRefusesAZip64LocatorPointingPastTheEnd and catalogRefusesALocalHeaderOffsetThatOverflows killed the test process with signal 5 (UInt64 overflow trap in ZipCatalog.read). deflate64FallbackRefusesACompressedSizeThatOverflows, driving Deflate64.extract directly, also died with signal 5 (dataOffset + compSize in locateEntry); through Archive.extract libarchive refuses that entry first, so the Deflate64 traps are reachable only by calling the decoder. A crafted Zip64 locator pointing past the end did not trap Deflate64.locateEntry: the seek succeeds, the short read is ignored, and the 32-bit directory is used.

## 2026-11-01

Before the fix, bomb guard: extractsAHundredMebibytesOfZeros failed with suspiciousArchive("The entry “disk.img” expands to more than 1,000× the archive’s size…"). stopsAManyEntryBombBeforeAGigabyte (16 × 256 MiB, 1.5 GB free) got noSpace(needed: 268435456, available: 157822720) after writing more than 1 GB. stopsABombHiddenBehindPaddingWhileStreaming extracted all 2 GiB without complaint. refusesATenGigabyteSingleEntryBombBeforeWritingAnything already passed (10 GiB at ~1,030:1 is just over the old 1,000:1 line). stopsADeflate64EntryThatExpandsPastItsDeclaredSize decoded all 8 MiB of a 1 MiB entry and only then failed with unreadable("Corrupt Deflate64 data."). deflate64AsksTheBombGuardBeforeWritingEachWindow cannot compile before the fix: the decoder has no guard to ask.

## 2026-11-01

A Deflate64 bomb at the real 1 GB floor is not tested end to end: the debug-build decoder makes about 10 MB/s (64 MiB took 6.9 s), so a gigabyte would take minutes. The decoder's wiring is tested directly with a stand-in guard instead.

## 2026-11-01

deflate64FallbackRefusesADirectoryThatOverflows (a Zip64 end record claiming a directory at UInt64.max - 10) killed the process with signal 5 with the old 'cdOffset + cdSize <= fileSize' put back, and passes with the subtraction form. Both locateEntry tests drive Deflate64.extract directly because libarchive rejects these files before it would fall back.

## Result

ZipCatalog and Deflate64.locateEntry now check every file-supplied offset by subtraction, so a hostile ZIP throws unreadable instead of trapping. The bomb guard (Archive.ExpansionGuard) refuses no ratio below 1 GB of output. Past that it refuses more than 100:1, checked two ways: up front, a declared size against the whole file; while streaming, bytes written against the compressed bytes read so far (archive_filter_bytes). 100 MiB of zeros extracts. A 10 GB bomb is refused before writing anything. A 16 × 256 MiB bomb stops at 805 MB, and a bomb padded to look plausible stops at 1 GB while streaming. The Deflate64 decoder stops at its declared size and asks the same guard before each 64 KB window. The real 1 GB limit through Deflate64 is tested only with a stand-in guard, because the debug decoder is too slow to produce a gigabyte in a test.
