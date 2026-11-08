---
id: 93
uid: bb249fd5-c8b8-4fb9-81e2-8558fa72817d
title: Open split archives from any of their pieces
type: feature
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
depends_on:
- 92
created: 2026-11-06
updated: 2026-11-07
closed_at: 2026-11-07
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

- [x] Each format the spike found readable opens from its first piece and from a later one, using new fixtures
- [x] A missing piece gives an error naming that piece, covered by a test
- [x] Split archives open read-only as imports, so autosave can never overwrite a piece

## 2026-11-07

Added Archive.resolveSplitPieces, Archive.isSplitArchive, Archive.openReader (using archive_read_open_filenames for .partN.rar, .rar+.r00, .z01+.zip, and .7z.001, and temporary concatenation for plain .001 chains), ArchiveError.missingSplitPiece, Info.plist split extensions, and read-only import handling in DocumentController and ArchiveDocument.

## Result

Split archives (.partN.rar, .rar+.r00, .z01+.zip, .7z.001, and .001) open read-only from any piece and report any missing piece by name.
