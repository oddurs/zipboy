---
id: 38
uid: b4244c29-35ad-405a-933a-e15eb5b74564
title: Offer once to open ZIPs with Zipboy
type: feature
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
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
- [ ] The offer appears at most once per Mac account
- [ ] Settings has the same switch for anyone who said no
