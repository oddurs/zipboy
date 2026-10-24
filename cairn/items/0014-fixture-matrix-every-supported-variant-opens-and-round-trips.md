---
id: 14
uid: 52b9158b-6ffc-4800-a598-e22018ea2610
title: 'Fixture matrix: every supported variant opens and round-trips'
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
depends_on:
- 13
- 54
- 55
- 56
created: 2026-10-20
updated: 2026-10-23
closed_at: 2026-10-23
priority: p0
effort: m
area: quality
---

## Problem

Only a handful of formats are tested, and the RAR fixture is RAR4 only.

## Proposal

Generate small fixtures with a script where tools allow (bsdtar, ditto, zip), check in the rest, and add a parameterized kit test that opens each, compares the listing and contents with an expected manifest, and for ZIPs saves and re-reads.

## Acceptance criteria

- [x] One fixture per supported variant from the spike's table, each under 64 KB
- [x] `scripts/make-fixtures` regenerates the generated ones
- [x] A parameterized test covers every fixture: listing, contents, and for ZIPs a save round trip
- [x] Each unsupported variant fails with a message that names the format

## 2026-10-23

Evidence: scripts/make-fixtures (uv run, stdlib only, ruff clean) generates 31 archives and is safe to run twice; 7 RAR files are libarchive's, credited in Fixtures/README.md. Largest fixture 14.6 KB; the ISO is stored gzipped (1.3 KB) since an ISO can't be under ~370 KB, and libarchive reads it the same. FixtureMatrixTests.opensAsPromised ran all 38 cases (checked in the verbose log): listing, hello/world contents, password required then accepted for the three encrypted ZIPs, the symlink target, and a save round trip with byte-identical files for every ZIP. everyFixtureHasACase fails if a fixture is added without a case. Unsupported variants: Deflate64 fails naming 'deflation-64-bit'; a plain gzipped file fails as 'Unrecognized archive format', which is right since it names no archive format; encrypted 7z and RAR are covered by saysWhenEncryptionIsUnsupported. zstd tar is left out: it reads only through a zstd program on PATH, which a stock Mac lacks.

## Result

38-variant fixture matrix with a parameterized test and scripts/make-fixtures.
