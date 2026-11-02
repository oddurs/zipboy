---
id: 18
uid: e5f8d94e-b43e-4c72-a1dd-1bdaf7a07bc7
title: 'ZipCatalog: read a ZIP''s central directory without unpacking'
type: feature
status: backlog
milestone: v0.2
depends_on:
- 17
created: 2026-10-20
updated: 2026-11-01
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
- [ ] Handles Zip64 archives over 4 GB and with over 65,535 entries
- [x] Rejects truncated and self-overlapping central directories with a typed error, covered by tests
- [ ] Reads a 100,000-entry catalog in under 200 ms

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. ZipCatalog exists. Criterion 1: catalogParsesStandardAndMatrixZipsAndMatchesTree parses the matrix ZIPs and checks names against the tree. Criterion 3: the same test expects a typed ArchiveError for a truncated file. Open: criterion 2 (no archive over 4 GB or 65,535 entries is tested; only zip-zip64 from the matrix) and criterion 4 (the benchmark reads 200 entries, not 100,000). The review found offset arithmetic that traps on a crafted Zip64 locator; 0069 fixes it.
