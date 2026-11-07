---
id: 104
uid: 5a399866-2804-401e-9284-85feb60d078d
title: Show what's taking up the space in an archive
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: s
area: browser
---

## Problem

The list shows folder sizes one level at a time, so finding what makes an archive big takes digging.

## Proposal

Sorting by size already works per folder. Add a View > Largest Items list across the whole archive, the
cheap version of a treemap. Draw a treemap only if that proves not to be enough.

## Acceptance criteria

- [ ] Largest Items lists the biggest files in the archive, whatever folder they're in, and selecting one reveals it
