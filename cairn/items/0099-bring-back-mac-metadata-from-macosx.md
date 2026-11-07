---
id: 99
uid: 16f400ec-449f-48bf-a795-31fa20d3f62d
title: Bring back Mac metadata from __MACOSX
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: archive
---

## Problem

ZIPs made on a Mac keep resource forks and extended attributes in `__MACOSX/._name` files.
`EntryPath.isJunk` drops those, so tags, Finder comments, and old resource forks are lost on extract.

## Proposal

Read each AppleDouble file while extracting and apply what it holds to the file it belongs to, instead of
dropping it. Quarantine from the archive itself wins over anything stored in the entry.

## Acceptance criteria

- [ ] A Finder tag on a file zipped by Archive Utility survives extraction, using a new fixture
- [ ] `__MACOSX` and `._` files still never appear in the list or the output
- [ ] A malformed AppleDouble file is ignored rather than failing the extract
