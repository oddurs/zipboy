---
id: 14
uid: 52b9158b-6ffc-4800-a598-e22018ea2610
title: 'Fixture matrix: every supported variant opens and round-trips'
type: feature
status: backlog
milestone: v0.1
depends_on:
- 13
- 54
- 55
- 56
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: quality
---

## Problem

Only a handful of formats are tested, and the RAR fixture is RAR4 only.

## Proposal

Generate small fixtures with a script where tools allow (bsdtar, ditto, zip), check in the rest, and add a parameterized kit test that opens each, compares the listing and contents with an expected manifest, and for ZIPs saves and re-reads.

## Acceptance criteria

- [ ] One fixture per supported variant from the spike's table, each under 64 KB
- [ ] `scripts/make-fixtures` regenerates the generated ones
- [ ] A parameterized test covers every fixture: listing, contents, and for ZIPs a save round trip
- [ ] Each unsupported variant fails with a message that names the format
