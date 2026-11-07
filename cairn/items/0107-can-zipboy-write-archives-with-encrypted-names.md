---
id: 107
uid: 4de6da3a-2abc-48e7-a6ce-2721492fab6c
title: Can Zipboy write archives with encrypted names?
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

7z can encrypt file names as well as contents, so a stolen archive doesn't reveal what's in it.
Zipboy can only write passwords into ZIPs (`ArchiveError.cantEncrypt`), and libarchive's 7z writer doesn't
appear to encrypt at all. Is there any way to offer this without bundling a second compression library?

## Why it matters

It's the one privacy feature ZIP can't give, but a dependency has to earn its place, and 0049 already
asks what writing 7z should mean.

## Timebox

Half a day, with 0049. The leading guess: not without a dependency, in which case the answer is no.

## Answer
