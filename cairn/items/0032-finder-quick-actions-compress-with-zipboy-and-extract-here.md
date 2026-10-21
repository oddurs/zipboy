---
id: 32
uid: 732f6783-c553-4e33-ba28-5531253a17d8
title: 'Finder Quick Actions: Compress with Zipboy and Extract Here'
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: system
---

## Problem

Making or unpacking a zip from the Finder means opening the app first.

## Proposal

Two Services declared in Info.plist, which Finder shows under Quick Actions: Compress with Zipboy makes a ZIP next to the selection, named as Finder's Compress names it; Extract Here does what the toolbar Extract does, without opening a window.

## Acceptance criteria

- [ ] Both appear in Finder's context menu under Quick Actions after the first launch
- [ ] Compress names the result after the item, or “Archive.zip” for several, never overwriting
- [ ] Extract Here on several archives extracts each next to itself
- [ ] Neither opens a window unless a password is needed
