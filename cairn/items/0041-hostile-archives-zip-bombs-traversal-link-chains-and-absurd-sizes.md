---
id: 41
uid: 941f5280-5cb7-4cec-afa3-5c4258328e8a
title: 'Hostile archives: zip bombs, traversal, link chains, and absurd sizes'
type: feature
status: backlog
milestone: v1.0
depends_on:
- 12
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: archive
---

## Problem

Path traversal and link stacking are handled, but a zip bomb would fill the disk, and absurd declared sizes are trusted.

## Proposal

A hostile-archive suite and the guards it needs: a compression-ratio and total-size limit with a clear message, a free-space check against declared sizes, entry-count limits, and refusal of absurd values.

## Acceptance criteria

- [ ] 42.zip and a 10 GB single-entry bomb stop with a message before using more than 1 GB
- [ ] Every traversal, absolute-path, and link-chain case in the suite is refused, covered by tests
- [ ] Declared sizes that disagree with the data stop extraction with a typed error
