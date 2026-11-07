---
id: 95
uid: 25f38bee-4862-4334-8b0f-c0099da4142d
title: Extract many archives in one go
type: feature
status: backlog
milestone: v0.4
created: 2026-11-06
updated: 2026-11-06
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

- [ ] Extracting five archives shows one progress bar and one finish notice, covered by a test on the task
- [ ] One damaged archive among five doesn't stop the other four, and the summary names it
- [ ] Unpacking nested archives stops at the depth limit, covered by a test with an archive that holds itself
