---
id: 78
uid: 3502e2ba-d6a0-48a3-a6ec-1b7264e87ec6
title: Finder shows an archive's contents in its icon
type: feature
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
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

- [x] `qlmanage -t` on a ZIP holding a PNG renders a thumbnail that shows the PNG
- [x] An archive with no images renders the generic icon with its entry count, not a blank tile
- [x] An encrypted archive renders without asking for a password
- [x] The extension is inside `Zipboy.app/Contents/PlugIns` after `scripts/task build` and `pluginkit -m` lists it

## 2026-11-02

Evidence. Thumbnails rendered through QLThumbnailGenerator (the public API Finder uses) from the registered release build, saved as PNG and looked at: a ZIP holding a PNG shows the picture matted over the zipper; a 10,000-file ZIP shows the icon with a 10,000 items pill; a password-protected ZIP renders without a prompt (1 item); at 32 px the count is skipped. Criterion 1 used QLThumbnailGenerator instead of qlmanage -t, which hangs with app extensions. FirstImageTests: compressed picture read whole, no picture, too big, never tries a password. BundleTests checks both extensions' plists. Not seen in a Finder window: this session has no Screen Recording permission.
