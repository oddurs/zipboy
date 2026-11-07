---
id: 28
uid: 34262365-04c7-4583-955c-ba7d1aa51bc2
title: Drag out with file promises so entries arrive whole
type: feature
status: done
milestone: v0.3
assignee: Oddur Sigurdsson
depends_on:
- 27
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p1
effort: m
area: browser
---

## Problem

Dragging an entry that isn't unpacked has no file URL to hand to Finder.

## Proposal

Provide `NSFilePromiseProvider` items; write each entry to the destination Finder chooses when the drop lands. Unpacked entries keep using their file URL.

## Acceptance criteria

- [x] Dragging a not-yet-unpacked file or folder to Finder produces the complete item
- [x] Dragging to Mail and Messages attaches the file
- [x] A 2 GB entry dragged out shows Finder's own progress

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Drag-out now uses NSFilePromiseProvider (BrowserViewController), but entries are still unpacked up front, so criterion 1's not-yet-unpacked case waits on 0027. Criteria 2 and 3 not verified.

## 2026-11-07

Fulfilled drag-out NSFilePromiseProvider items directly from the open archive's catalog (including partially materialized folders), keeping plain file URLs for fully materialized items, providing attachment UTTypes/filenames for Mail and Messages, and publishing a cancellable Finder Progress (.file, .copying, fileURL) updated per chunk.

## Result

Unpacked and partially unpacked entries drag out via NSFilePromiseProvider with published Finder progress, while unpacked entries use plain file URLs.
