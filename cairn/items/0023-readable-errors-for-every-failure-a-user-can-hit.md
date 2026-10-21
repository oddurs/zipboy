---
id: 23
uid: fad3f16e-aaa4-4ce2-8053-0ab367e2a549
title: Readable errors for every failure a user can hit
type: feature
status: backlog
milestone: v0.2
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: m
area: document
---

## Problem

Failures surface libarchive's or POSIX's wording, such as “Truncated input file (needed 1048576 bytes, only 0 available)”.

## Proposal

Map each failure to a sentence a person understands plus what they can do: corrupt or truncated archive (“may not have finished downloading”), unsupported variant (names it), permission denied on save (offers Duplicate), disk full on save, wrong password.

## Acceptance criteria

- [ ] Each case above has a message naming the file and the next step
- [ ] The mapping lives in ZipboyKit and is unit-tested per case
- [ ] No libarchive or POSIX wording reaches an alert, except in a Details disclosure
