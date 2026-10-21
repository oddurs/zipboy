---
id: 57
uid: 6a872abc-7732-423c-aa99-ef95fc280019
title: Read Deflate64 ZIPs, which Windows makes for large files
type: feature
status: backlog
milestone: v0.2
depends_on:
- 13
created: 2026-10-20
updated: 2026-10-20
priority: p2
effort: l
area: archive
---

## Problem

Windows Explorer's "Send to compressed folder" uses Deflate64 for files over 2 GB. libarchive can't read it
("Unsupported ZIP compression method (9: deflation-64-bit)"), so Zipboy can't open those archives at all.

## Proposal

Read Deflate64 entries through ZipCatalog with an inflate64 decoder of our own (Deflate64 is Deflate with a
64 KB window and two extra length codes), falling back to libarchive for everything else.

## Acceptance criteria

- [ ] A Deflate64 fixture made with `7zz a -tzip -mm=Deflate64` opens and its contents match the source
- [ ] A 3 GB Deflate64 entry made by Windows Explorer opens and extracts correctly
- [ ] The decoder is fuzzed with the other readers in v1.0
