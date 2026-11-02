---
id: 23
uid: fad3f16e-aaa4-4ce2-8053-0ab367e2a549
title: Readable errors for every failure a user can hit
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-11-02
priority: p1
effort: m
area: document
---

## Problem

Failures surface libarchive's or POSIX's wording, such as “Truncated input file (needed 1048576 bytes, only 0 available)”.

## Proposal

Map each failure to a sentence a person understands plus what they can do: corrupt or truncated archive (“may not have finished downloading”), unsupported variant (names it), permission denied on save (offers Duplicate), disk full on save, wrong password.

## Acceptance criteria

- [x] Each case above has a message naming the file and the next step
- [x] The mapping lives in ZipboyKit and is unit-tested per case
- [x] No libarchive or POSIX wording reaches an alert, except in a Details disclosure

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. ArchiveError.describe(_:fileName:) maps failures to sentences, with a Details disclosure in Prompts. Criterion 2: mapsEveryFailureToHumanReadableExplanation. Criteria 1 and 3 not verified case by case.

## 2026-11-02

2026-11-02: in the completeness pass, recovery buttons (Duplicate on a permission error, Show in Finder on a full disk) are part of finishing criterion 1, not a separate item.

## 2026-11-02

Evidence. ErrorWordingTests runs eleven failures (truncated, damaged, unsupported method, encrypted 7z, wrong password, no permission, read-only volume, unwritable, three kinds of full disk) and requires each to name the file and give a next step, with no libarchive or system wording in the title or message. Unsupported methods are named from libarchive's bracket (“lzma”). The next step is now a button where there is one: Duplicate… for permission errors, Open Storage Settings for a full disk, through NSError recovery options on the document (ErrorRecoveryTests). Details stay in Prompts.makeErrorAlert's accessory, never the message. Not seen on screen this session.
