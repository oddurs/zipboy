---
id: 1
uid: 4294b8e5-86ab-41ab-a4d6-1e09c8862033
key: v0.1
title: First release
type: milestone
status: backlog
created: 2026-10-20
updated: 2026-10-20
priority: p2
due: 2026-11-20
---

## Ships

A stranger downloads a notarized Zipboy, opens any common archive, previews it, changes it, and extracts from it, and every change lands in a correct ZIP without their original ever being at risk.

## Done when

- [ ] A tagged commit produces a notarized, stapled DMG that opens on a clean Mac without warnings
- [ ] Every pull request runs `scripts/task check` in CI
- [ ] The fixture matrix opens and round-trips every variant the support table claims
- [ ] No open bug that can lose or corrupt a user's data

## Explicitly not in this milestone

- Fast saves for huge archives (v0.2)
- Opening without unpacking (v0.3)
- Finder integration and auto-updates (v0.4)
