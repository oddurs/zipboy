---
id: 94
uid: ab9bd6a2-1405-475c-87ec-c699b8d36abb
title: Make split archives
type: feature
status: backlog
milestone: later
depends_on:
- 93
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: archive
---

## Problem

Size limits on email and file sharing mean a big archive sometimes has to go in pieces.

## Proposal

An option in File > Export… to split at a chosen size, writing `.zip`, `.z01` and so on, in the format
the reading side already understands. Deferred until reading split archives works, and until someone
asks: most sharing tools now take large files.

## Acceptance criteria

- [ ] An export split at 10 MB produces pieces no larger than that, which Zipboy and `unzip` both read back
