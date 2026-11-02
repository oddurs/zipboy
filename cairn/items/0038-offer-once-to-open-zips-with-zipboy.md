---
id: 38
uid: b4244c29-35ad-405a-933a-e15eb5b74564
title: Offer once to open ZIPs with Zipboy
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-11-01
priority: p2
effort: s
area: system
---

## Problem

Zipboy registers at Alternate rank, so double-clicking a ZIP still opens Archive Utility, and most people never find Open With.

## Proposal

On the third launch, one quiet sheet offers to make Zipboy the app for ZIP files, using `NSWorkspace.setDefaultApplication`. Never asks again either way.

## Acceptance criteria

- [ ] Accepting makes ZIPs open in Zipboy from the Finder
- [x] The offer appears at most once per Mac account
- [x] Settings has the same switch for anyone who said no

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Criterion 2: Settings.recordLaunchAndShouldOfferDefaultHandler offers once, on the third launch (settingsWindowReflectsAndRestoresDefaults). Criterion 3: Settings has Set for ZIP and Set for All Archives. Criterion 1 not verified on a real Mac; setDefaultApplication's completion discards its error.
