---
id: 26
uid: 9aa7c924-2fe4-4cea-a0ee-5583f837e035
title: Browse a ZIP from its catalog before anything is unpacked
type: feature
status: backlog
milestone: v0.3
depends_on:
- 20
- 25
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: browser
---

## Problem

The list is built by scanning the unpacked workspace, so nothing shows until everything is written.

## Proposal

Build the `Node` tree from ZipCatalog for ZIPs. Sizes, dates, and kinds come from the catalog; the workspace holds only what has been used or changed.

## Acceptance criteria

- [ ] A 100,000-entry ZIP lists in under 1 second
- [ ] Sorting, search, and folder sizes work before anything is unpacked
- [ ] Opening a ZIP writes nothing under `$TMPDIR/Zipboy` until an entry is used
