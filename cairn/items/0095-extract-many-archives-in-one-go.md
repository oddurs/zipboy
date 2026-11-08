---
id: 95
uid: 25f38bee-4862-4334-8b0f-c0099da4142d
title: Extract many archives in one go
type: feature
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
created: 2026-11-06
updated: 2026-11-07
closed_at: 2026-11-07
priority: p2
effort: m
area: shell
---

## Problem

Selecting a dozen archives in Finder and opening them makes a dozen windows. The Extract Here service
handles several, one after another, but shows no combined progress and stops at the first failure.

## Proposal

Make the service and AppleScript `extract` run the archives as one `LongTask`, carrying on past a failure
and reporting at the end which ones failed and why. An option in Settings also unpacks archives found
inside, one level deep at a time, bounded by the same bomb guards as any extract.

## Acceptance criteria

- [x] Extracting five archives shows one progress bar and one finish notice, covered by a test on the task
- [x] One damaged archive among five doesn't stop the other four, and the summary names it
- [x] Unpacking nested archives stops at the depth limit, covered by a test with an archive that holds itself

## 2026-11-07

AppDelegate.extractBatch and Scripting.extract run multiple archives as a single LongTask, continuing past damaged archives to report failures at the end, and optionally unpacking nested archives up to Settings.maxNestedArchiveDepth.

## Result

Multi-archive Extract Here and AppleScript extract run as one LongTask with a combined progress bar, failure summary, and depth-limited nested archive unpacking.
