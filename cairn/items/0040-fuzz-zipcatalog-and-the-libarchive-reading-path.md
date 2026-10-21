---
id: 40
uid: 25bb6587-e39c-457c-943e-a0db5d3f50b1
title: Fuzz ZipCatalog and the libarchive reading path
type: chore
status: backlog
milestone: v1.0
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: quality
---

## Problem

Zipboy parses untrusted files from the internet. The catalog parser is new code, and the extraction path has only hand-written tests.

## Proposal

A libFuzzer target for ZipCatalog and one that runs `Archive.extract` into a sandboxed temporary folder, seeded from the fixture matrix. Run 24 hours before release and nightly after.

## Acceptance criteria

- [ ] Both fuzz targets build with `swift build -Xswiftc -sanitize=fuzzer`
- [ ] 24 hours of fuzzing find no crash, hang, or write outside the root
- [ ] Every crash found becomes a fixture and a regression test
