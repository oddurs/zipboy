---
id: 93
uid: bb249fd5-c8b8-4fb9-81e2-8558fa72817d
title: Open split archives from any of their pieces
type: feature
status: backlog
milestone: v0.4
depends_on:
- 92
created: 2026-11-06
updated: 2026-11-06
priority: p1
effort: m
area: archive
---

## Problem

Big downloads often come as `.part1.rar`, `.z01`, or `.001` pieces. Zipboy reads a single file, so these
fail with an error that makes the app look broken.

## Proposal

Given any piece, find its siblings by name, check none is missing, and read them as one archive, by the
method the spike settles on. Add the extensions to the document types in `Info.plist`. A missing piece
says which one, rather than reporting a damaged archive.

## Acceptance criteria

- [ ] Each format the spike found readable opens from its first piece and from a later one, using new fixtures
- [ ] A missing piece gives an error naming that piece, covered by a test
- [ ] Split archives open read-only as imports, so autosave can never overwrite a piece
