---
id: 96
uid: 395cf111-7977-4a1c-a1c0-f876d1cfc862
title: Keep going past a damaged entry and save what's readable
type: feature
status: backlog
milestone: v1.0
created: 2026-11-06
updated: 2026-11-06
priority: p2
effort: m
area: archive
---

## Problem

`Archive.extract` stops at the first bad entry, so one damaged file loses everything after it. Listing
already tolerates a damaged tail (`Archive.list`), so the app can show entries it then can't deliver.

## Proposal

When an entry fails, skip it, carry on, and finish with a report of what was skipped, as `ExtractSummary`
already does for unsafe entries. Keep this out of the normal path's silence: the person is told the
result is incomplete, and which files are missing.

## Acceptance criteria

- [ ] A ZIP with one corrupted entry in the middle extracts every other entry, using a new fixture
- [ ] The alert names the entries that were skipped
- [ ] A truncated archive yields the entries before the cut, and says the rest is gone
