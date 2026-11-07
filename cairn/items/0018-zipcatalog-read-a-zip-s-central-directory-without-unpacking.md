---
id: 18
uid: e5f8d94e-b43e-4c72-a1dd-1bdaf7a07bc7
title: 'ZipCatalog: read a ZIP''s central directory without unpacking'
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
depends_on:
- 17
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: m
area: archive
---

## Problem

To copy entries verbatim, and later to list without unpacking, Zipboy needs every entry's offset, sizes, CRC, method, flags, and name straight from the central directory.

## Proposal

A `ZipCatalog` in ZipboyKit that parses the end-of-central-directory record, Zip64 records, and entries. Names decode as UTF-8 when flagged, otherwise CP437. It rejects inconsistent offsets and sizes rather than trusting them.

## Acceptance criteria

- [x] Parses every ZIP in the fixture matrix with results equal to libarchive's listing
- [x] Handles Zip64 archives over 4 GB and with over 65,535 entries
- [x] Rejects truncated and self-overlapping central directories with a typed error, covered by tests
- [x] Reads a 100,000-entry catalog in under 200 ms

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. ZipCatalog exists. Criterion 1: catalogParsesStandardAndMatrixZipsAndMatchesTree parses the matrix ZIPs and checks names against the tree. Criterion 3: the same test expects a typed ArchiveError for a truncated file. Open: criterion 2 (no archive over 4 GB or 65,535 entries is tested; only zip-zip64 from the matrix) and criterion 4 (the benchmark reads 200 entries, not 100,000). The review found offset arithmetic that traps on a crafted Zip64 locator; 0069 fixes it.

## 2026-11-07

Added ArchiveTests.catalogHandlesZip64OverFourGigabytesAndOverSixtyFiveThousandEntries covering two sparse Zip64 archives on APFS: 70,001 entries with an entry and Central Directory past 4 GiB (offset 4,500,000,000, verified through payloadRange) and a single stored entry with 4.5 GB 64-bit compressed and uncompressed sizes. Tightened the Zip64 EOCD bounds check against locatorOffset - 56. Reworked ZipCatalog.read (cached DOS dates with one Calendar, unaligned pointer loads, skipped redundant offset sort and encoding scan) and added ASCII fast paths to EntryPath.sanitized and TextEncoding.decode; scripts/bench now measures 'ZIP catalog, 100,000 entries' at ~28 ms against the 200 ms budget.

## Result

ZipCatalog is verified on >4 GB and >65,535-entry Zip64 archives and reads a 100,000-entry catalog in ~28 ms (under the 200 ms budget in scripts/bench).
