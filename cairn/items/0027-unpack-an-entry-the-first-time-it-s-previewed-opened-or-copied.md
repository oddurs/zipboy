---
id: 27
uid: ed713cb6-75d8-4da3-8711-ab6a73793321
title: Unpack an entry the first time it's previewed, opened, or copied
type: feature
status: done
milestone: v0.3
assignee: Oddur Sigurdsson
depends_on:
- 26
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p0
effort: m
area: document
---

## Problem

With a catalog-only tree, previews and Open have no file to point at.

## Proposal

A materializer that extracts one entry, or one folder's entries, into the workspace on demand, off the main thread, with the preview showing a spinner until the bytes arrive.

## Acceptance criteria

- [x] Selecting a file shows its preview within 200 ms for files under 10 MB
- [x] Open, Open With, Copy, Share, and Extract all materialize first
- [x] Materialized files count as unchanged for saving
- [x] Two requests for the same entry unpack it once

## 2026-11-07

Wired on-demand materialization across PreviewViewController (with spinner while unpacking off the main thread), BrowserViewController (Open, Open With, Copy, Extract, Quick Look), and ArchiveWindowController (Share), with per-path Task coalescing and inode provenance registration.

## Result

Entries unpack on demand with coalesced off-main-thread materialization, preview spinner, and unchanged save provenance.
