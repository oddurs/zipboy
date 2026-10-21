---
id: 34
uid: f93b2186-e25c-4100-85c2-85324150d97c
title: Updates arrive without the user doing anything
type: feature
status: backlog
milestone: v0.4
depends_on:
- 10
- 33
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: m
area: distribution
---

## Problem

An installed Zipboy never learns there is a newer one.

## Proposal

Implement what the updates spike decided: check daily, download in the background, verify the signature, and offer to restart once, quietly.

## Acceptance criteria

- [ ] An installed v0.4.0 offers v0.4.1 within a day of its release
- [ ] An update with a bad signature is refused and logged
- [ ] Updating never interrupts an unsaved document
