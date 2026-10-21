---
id: 25
uid: c7a8b41b-1179-44d6-afb5-a2b514cc6aab
title: What breaks if files exist only once they're used?
type: spike
status: backlog
milestone: v0.3
depends_on:
- 18
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: s
area: document
---

## Question

If a ZIP is browsed from its catalog and an entry is unpacked only on first use, what depends on the file being there today? Quick Look, Open With, drag out, copy, folder sizes, the FileWatcher, search, thumbnails, extract. Where does each one need the bytes, and how long can it wait?

## Why it matters

Opening is the first thing anyone does, and today it costs the full unpacked size in time and disk.

## Timebox

One day. The answer lists every touch point with a plan, and confirms solid RAR and 7z stay fully unpacked.

## Answer
