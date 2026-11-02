---
id: 78
uid: 3502e2ba-d6a0-48a3-a6ec-1b7264e87ec6
title: Finder shows an archive's contents in its icon
type: feature
status: backlog
milestone: v0.4
depends_on:
- 30
created: 2026-11-02
updated: 2026-11-02
priority: p2
effort: m
area: system
---

## Problem

In Finder's icon and gallery views, and in open panels, every ZIP shows the same generic zipper
page. Telling archives apart means opening them.

## Proposal

A Quick Look thumbnail extension (`QLThumbnailProvider`) in the same bundle layout that 0030 settles
for the preview extension. It draws the system's archive document icon with the first image entry
inset as a picture, or the archive's entry count when there is no image. It reads only the listing
and at most one entry, never unpacking the whole archive.

## Acceptance criteria

- [ ] `qlmanage -t` on a ZIP holding a PNG renders a thumbnail that shows the PNG
- [ ] An archive with no images renders the generic icon with its entry count, not a blank tile
- [ ] An encrypted archive renders without asking for a password
- [ ] The extension is inside `Zipboy.app/Contents/PlugIns` after `scripts/task build` and `pluginkit -m` lists it
