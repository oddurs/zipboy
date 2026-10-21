---
id: 45
uid: c5d39e11-bf95-41ea-968a-d1e151e15942
title: Release checklist and the v1.0 tag
type: chore
status: backlog
milestone: v1.0
depends_on:
- 42
- 43
- 44
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: s
area: distribution
---

## Problem

A release is many steps and the first one will be done under pressure.

## Proposal

A checklist in `docs/releasing.md` that the release follows: version, changelog, beta sign-off, tag, verify the notarized DMG on a clean account, update the landing page.

## Acceptance criteria

- [ ] `docs/releasing.md` covers every step from changelog to announcement
- [ ] v1.0.0 is tagged by following it, and every box is ticked in the release PR
