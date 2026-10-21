---
id: 2
uid: 5af95139-3fc7-46bb-ac96-cbfaf6d58dac
key: v0.2
title: Saves in seconds
type: milestone
status: backlog
depends_on:
- 1
created: 2026-10-20
updated: 2026-10-20
priority: p2
due: 2026-12-18
---

## Ships

Changing one file in a multi-gigabyte ZIP saves in seconds, because everything unchanged is copied byte for byte instead of being compressed again.

## Done when

- [ ] A one-file change to a 2 GB ZIP saves in under 3 seconds on an M1
- [ ] Unchanged entries in a saved archive are byte-identical to the original's
- [ ] The benchmark gate runs in CI and fails on a 20% regression

## Explicitly not in this milestone

- Lazy unpacking on open (v0.3)
- Writing any format but ZIP
