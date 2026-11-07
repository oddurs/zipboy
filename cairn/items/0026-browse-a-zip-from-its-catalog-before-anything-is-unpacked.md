---
id: 26
uid: 9aa7c924-2fe4-4cea-a0ee-5583f837e035
title: Browse a ZIP from its catalog before anything is unpacked
type: feature
status: done
milestone: v0.3
assignee: Oddur Sigurdsson
depends_on:
- 20
- 25
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: m
area: browser
---

## Problem

The list is built by scanning the unpacked workspace, so nothing shows until everything is written.

## Proposal

Build the `Node` tree from ZipCatalog for ZIPs. Sizes, dates, and kinds come from the catalog; the workspace holds only what has been used or changed.

## Acceptance criteria

- [x] A 100,000-entry ZIP lists in under 1 second
- [x] Sorting, search, and folder sizes work before anything is unpacked
- [x] Opening a ZIP writes nothing under `$TMPDIR/Zipboy` until an entry is used

## 2026-11-07

Opening an unencrypted ZIP in ArchiveDocument now parses ZipCatalog, allocates a lazy Workspace without creating directories under $TMPDIR/Zipboy, and builds the Node tree via Node.fromCatalog/Node.scan in O(N) with cached UTType kind descriptions and recursive folder sizes.

## Result

Node.fromCatalog and Node.scan merge ZipCatalog entries with on-disk Workspace files, Workspace(lazy: true) defers directory creation until materialization or edits, and Archive.extractEntry + ArchiveDocument.materialize unpack individual entries on demand.
