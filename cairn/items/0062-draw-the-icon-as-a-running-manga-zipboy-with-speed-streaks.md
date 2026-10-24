---
id: 62
uid: f3dcaa51-55ec-4a7f-8e95-23cf2c8913ff
title: Draw the icon as a running manga Zipboy with speed streaks
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-10-24
updated: 2026-10-24
closed_at: 2026-10-24
priority: p1
area: shell
effort: s
---

## Problem

The app icon is a plain zipper on an orange squircle, without the Zipboy character the app is named for.

## Proposal

Draw Zipboy in `scripts/make-icon.swift` as a manga boy sprinting in side profile across the warm orange squircle, with spiky wind-swept hair, a zippered hoodie, a large zipper pull tab streaming behind his collar, an unzipping track in his wake, and sharp manga speed streaks. Regenerate `Resources/AppIcon.icns` and `docs/icon.png` (used as the logo in `README.md`).

## Acceptance criteria

- [x] `scripts/make-icon.swift` draws the side-profile running manga Zipboy with speed streaks
- [x] `Resources/AppIcon.icns` and `docs/icon.png` are regenerated from the script

## 2026-10-24

scripts/make-icon.swift now draws a side-profile manga Zipboy sprinting right across the orange squircle with wind-swept spiky hair, a zippered hoodie with gold teeth, a large zipper pull tab streaming from his collar, an unzipping track in his wake, and sharp manga speed lines; regenerated Resources/AppIcon.icns and docs/icon.png.

## Result

Resources/AppIcon.icns and docs/icon.png now show the running manga Zipboy with speed streaks.
