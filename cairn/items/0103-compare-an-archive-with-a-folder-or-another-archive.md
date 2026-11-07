---
id: 103
uid: 2a480213-8fc7-4cea-abf7-09da90023a5c
title: Compare an archive with a folder or another archive
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: browser
---

## Problem

There's no way to see what changed between two versions of an archive, or whether a backup matches the
folder it came from, short of extracting and diffing.

## Proposal

File > Compare With… lists entries added, removed, and changed, by size and CRC-32 from the catalog, so
ZIPs need no unpacking.

## Acceptance criteria

- [ ] Comparing two ZIPs reports added, removed, and changed entries, covered by a test
- [ ] Identical contents with different dates count as the same
