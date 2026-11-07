---
id: 92
uid: 1b7d4736-e418-47e8-9416-c42843e87cff
title: Which split archives can libarchive join?
type: spike
status: backlog
milestone: v0.4
created: 2026-11-06
updated: 2026-11-06
priority: p1
effort: s
area: archive
---

## Question

`archive_read_open_filenames` reads several files as one stream. Does the libarchive that ships with
macOS read each common kind of split archive through it: `.part1.rar`, `.r00`, `.z01` with `.zip`,
`.7z.001`, and plain `.001` pieces? Which need Zipboy to join the pieces itself first?

## Why it matters

Zipboy opens one file at a time, so opening part of a split archive fails or shows only that part.
The answer sets the size of the item that depends on this one.

## Timebox

Half a day. The leading guess: multi-volume RAR works through `archive_read_open_filenames`, and plain
`.001` pieces only need concatenating; split ZIP is the unknown, since its central directory is in the
last piece.

## Answer
