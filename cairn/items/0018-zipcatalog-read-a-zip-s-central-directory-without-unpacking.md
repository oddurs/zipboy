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
updated: 2026-10-20
priority: p0
effort: m
area: archive
---

## Problem

To copy entries verbatim, and later to list without unpacking, Zipboy needs every entry's offset, sizes, CRC, method, flags, and name straight from the central directory.

## Proposal

A `ZipCatalog` in ZipboyKit that parses the end-of-central-directory record, Zip64 records, and entries. Names decode as UTF-8 when flagged, otherwise CP437. It rejects inconsistent offsets and sizes rather than trusting them.

## Acceptance criteria

- [ ] Parses every ZIP in the fixture matrix with results equal to libarchive's listing
- [ ] Handles Zip64 archives over 4 GB and with over 65,535 entries
- [ ] Rejects truncated and self-overlapping central directories with a typed error, covered by tests
- [ ] Reads a 100,000-entry catalog in under 200 ms
