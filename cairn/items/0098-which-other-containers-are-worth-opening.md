---
id: 98
uid: 77c32028-a218-4996-a6d7-89db765f27a7
title: Which other containers are worth opening?
type: spike
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: s
area: archive
---

## Question

What would it take to open DMG, `.deb`, `.rpm`, `.msi`, and self-extracting `.exe` archives, and which are
worth it? Zipboy lists its formats explicitly (`Archive.formats`), and `.deb` is an `ar` holding tarballs,
which the current list can already half read. DMG would need `hdiutil`, not libarchive.

## Why it matters

Each format is more ways to fail on hostile input, and macOS already opens DMG itself, so this is only
worth it where people really do try to look inside these on a Mac.

## Timebox

Half a day. The leading guess: `.deb` and `.rpm` are cheap through libarchive, and DMG isn't worth it.
Decided already: Zipboy won't create self-extracting archives, which are Windows programs and of no use
on a Mac.

## Answer
