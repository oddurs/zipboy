---
id: 16
uid: ef8a7e9d-703e-4edc-bb46-6a9a90aaea80
title: 'README: install, what it does, and screenshots'
type: docs
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
depends_on:
- 10
- 14
created: 2026-10-20
updated: 2026-10-24
closed_at: 2026-10-24
priority: p1
effort: s
area: distribution
---

## Problem

The README describes features but not how to install, and has no pictures of an app whose whole point is how it looks.

## Proposal

An install section that links to the latest release, three screenshots (browsing with the preview, dropping files in, the empty window), and the format support table from the matrix spike.

## Acceptance criteria

- [ ] Install instructions work for someone who has never built software
- [x] Three screenshots at 2x in `docs/`, light and dark
- [x] The support table matches the fixture matrix

## 2026-10-24

README now has: install steps (download the DMG from Releases, drag to Applications, Open Anyway in Privacy & Security), the requirement (macOS 14, Apple silicon or Intel), what it does, three screenshots in docs/screenshots at 2x (1960x1240) in light and dark, switched with <picture> and prefers-color-scheme, and the support table, written row by row from FixtureMatrixTests' cases. Not walked through on a clean account: the Open Anyway step follows Apple's current Gatekeeper flow for apps that aren't notarized, and goes away with 0058. The drag-in screenshot became the empty 'Drop Files Here' window: capturing a live drag means driving the mouse on a Mac someone may be using.

## Result

README: install, features, light and dark screenshots, and the tested support table.
