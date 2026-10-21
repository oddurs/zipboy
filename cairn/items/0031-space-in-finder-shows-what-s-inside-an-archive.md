---
id: 31
uid: d3ca95f9-8e89-4a00-bf83-90834ffd1855
title: Space in Finder shows what's inside an archive
type: feature
status: backlog
milestone: v0.4
depends_on:
- 30
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: l
area: system
---

## Problem

Pressing Space on a ZIP in Finder shows a generic icon. Seeing inside means opening an app.

## Proposal

A Quick Look preview extension that lists the archive's contents as a compact tree with sizes, using ZipCatalog for ZIPs and libarchive's listing for the rest, without unpacking anything.

## Acceptance criteria

- [ ] Space on a ZIP, RAR, 7z, or tarball in Finder shows its tree within 300 ms for 10,000 entries
- [ ] Encrypted archives show their names when the format allows, and a lock otherwise
- [ ] The extension ships inside the notarized app and registers on first launch
