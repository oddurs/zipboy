---
id: 27
uid: ed713cb6-75d8-4da3-8711-ab6a73793321
title: Unpack an entry the first time it's previewed, opened, or copied
type: feature
status: backlog
milestone: v0.3
depends_on:
- 26
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: document
---

## Problem

With a catalog-only tree, previews and Open have no file to point at.

## Proposal

A materializer that extracts one entry, or one folder's entries, into the workspace on demand, off the main thread, with the preview showing a spinner until the bytes arrive.

## Acceptance criteria

- [ ] Selecting a file shows its preview within 200 ms for files under 10 MB
- [ ] Open, Open With, Copy, Share, and Extract all materialize first
- [ ] Materialized files count as unchanged for saving
- [ ] Two requests for the same entry unpack it once
