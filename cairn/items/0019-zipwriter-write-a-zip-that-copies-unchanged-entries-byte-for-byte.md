---
id: 19
uid: 60402f51-bf8a-45c4-a3f1-0c59140c145f
title: 'ZipWriter: write a ZIP that copies unchanged entries byte for byte'
type: feature
status: backlog
milestone: v0.2
depends_on:
- 18
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: l
area: archive
---

## Problem

Every save recompresses every file, so a small change to a large archive costs as much as making it from scratch.

## Proposal

A writer that takes a list of entries, each either a catalog entry to copy verbatim from the source file or a workspace file to compress, and writes local headers, data, and a central directory, using Zip64 where needed. Implements what the spike chose.

## Acceptance criteria

- [ ] Copied entries are byte-identical to the source's, headers included
- [ ] New entries are deflated or stored by the existing `ZipMethod` rule
- [ ] Output passes `unzip -t`, Archive Utility, and a re-read through ZipCatalog and libarchive
- [ ] Archives over 4 GB and with over 65,535 entries round-trip
- [ ] Encrypted archives follow the spike's answer, with a test
