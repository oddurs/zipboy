---
id: 29
uid: 08f9080e-598a-4747-a3b6-de13eb3f3014
title: Show and cancel progress for long adds and extracts
type: feature
status: planned
milestone: v0.3
created: 2026-10-20
updated: 2026-11-02
priority: p1
effort: m
area: shell
---

## Problem

Adding a large folder or extracting a large archive gives no sign of progress and can't be stopped.

## Proposal

Publish an `NSProgress` per operation, shown in the window's subtitle and, for extracts, on the destination file in Finder. Escape or the stop button cancels and cleans up.

## Acceptance criteria

- [x] Operations longer than 1 second show progress in the subtitle
- [ ] Extracting shows Finder's progress pie on the destination
- [x] Cancelling leaves neither partial files at the destination nor half-added items in the archive

## 2026-11-02

2026-11-02: the Dock tile and the finish notification are 0079, which builds on the Progress this item publishes.

## 2026-11-02

2026-11-02. Copies go through FileCopy (copyfile(3) with byte callbacks, cloning on APFS, which is instant and so never shows a bar). Adds and extracts are LongTasks on the document: the title stands in the subtitle, and after a second a strip under the toolbar shows a bar and a stop button; Escape stops too. A stopped add removes its staged copies and leaves the archive untouched; a stopped extract removes what it copied and the wrapping folder. Tests: FileCopyTests (4), LongTaskTests (4). Criterion 2 not ticked: each extracted item's Progress is published with kind .file and fileURL, which is what Finder draws its pie from, but it was not seen on screen (no Screen Recording permission this session).
