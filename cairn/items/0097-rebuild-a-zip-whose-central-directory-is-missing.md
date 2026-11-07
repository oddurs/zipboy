---
id: 97
uid: 4df2aff4-c085-485a-9552-4361c2cace20
title: Rebuild a ZIP whose central directory is missing
type: feature
status: backlog
milestone: v1.0
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: archive
---

## Problem

An interrupted download loses the end of a ZIP, and with it the central directory, so `ZipCatalog`
finds nothing, even though most of the data is intact.

## Proposal

When the end-of-central-directory record is missing, scan forward for local file headers and build the
catalog from those, as `zip -FF` does, opening the result as an untitled import. RAR recovery records are
out of scope: libarchive doesn't read them.

## Acceptance criteria

- [ ] A ZIP cut off partway lists and extracts every complete entry, using a new fixture
- [ ] The window says it was recovered, and the original file isn't changed
- [ ] A scan of random bytes finds nothing and ends quickly, covered by a test
