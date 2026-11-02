---
id: 72
uid: 15102396-5292-41a2-9b99-d2f133fd35c8
title: Reconcile the board with the 2026-11-01 batch
type: chore
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p1
effort: s
area: quality
---

## Problem

The 2026-11-01 batch filed four catch-all items (0063–0066) and built work that already had items of its
own: ZipCatalog (0018), ZipWriter (0019), entry tracking (0020), delta saves (0021), benchmarks (0022),
readable errors (0023), version stamping (0024), file promises (0028), Finder actions (0032), nested
archives (0036), spring-loading (0037), the default-app offer (0038), Keychain (0039), hostile archives
(0041), Help (0042), legacy encodings (0050), and Deflate64 (0057). Those items were left open with no
criteria ticked, so the board says none of it exists, while 0063–0066 claim everything is done. It also
shipped `Resources/Help.html`, which nothing loads.

## Proposal

Judge each original item's criteria against what main does and tests, tick only what is true, close
only what is fully true, and record the gaps and the follow-up items (0068–0071) on each. Point
0063–0066 at the items they overlapped. Remove the dead help page.

## Acceptance criteria

- [x] Every overlapped item has a note saying what the batch built, which criteria hold, and what is missing
- [x] Only criteria backed by a passing test, or code read for the purpose, are ticked
- [x] 0063–0066 each name the original items they overlapped and the follow-up fixes
- [x] `Resources/Help.html` is gone and the build no longer copies it
- [x] `cairn check` and `scripts/task check` pass

## Result

Every item the batch overlapped now says what exists, which criteria hold, and what is missing, with the follow-up fixes named. 0017 and 0037 closed; the rest stay open with honest ticks. Help.html removed; 0073 and 0074 filed.
