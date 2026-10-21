---
id: 12
uid: 432cb06f-e9f5-408b-be24-eb66d7ae4a7c
title: Check free space before unpacking
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-10-20
closed_at: 2026-10-20
priority: p1
effort: s
area: document
---

## Problem

Opening unpacks the whole archive into the temporary folder. On a nearly full disk it fails partway with a raw POSIX error and leaves a half-written workspace behind.

## Proposal

Before writing each entry, compare its size with the volume's available capacity for important usage. If it won't fit, stop, remove the workspace, and say how much is needed and how much is free.

## Acceptance criteria

- [x] Opening an archive larger than the free space shows “Not enough space to open “x.zip”. It needs about N GB; M GB is free.” and closes the window
- [x] No partial workspace is left in `$TMPDIR/Zipboy`
- [x] Covered by a kit test that injects a small capacity

## 2026-10-20

Evidence: ArchiveTests.stopsBeforeFillingTheDisk injects 1 MB of capacity; extracting a ZIP with a 3 MB file throws noSpace(needed: 3 MB, available: 1 MB) and leaves no big.bin. With the check removed it failed (extraction succeeded, big.bin written). On a real 10 MB disk image with the check bypassed, the mid-write ENOSPC also mapped to noSpace and the partial file was removed. In the app, a failing open shows the error sheet ('“x” couldn’t be opened.' plus the reason) and closing it closes the window with no workspace left, checked with a corrupt ZIP; the app can't be pointed at a small temp disk (Foundation ignores TMPDIR), so the no-space sheet itself was not seen on screen. The message says 'needs at least N' rather than 'about N': libarchive gives sizes per entry, not a total up front.

## Result

Extraction stops with noSpace before a file that won't fit; partial files are removed.
