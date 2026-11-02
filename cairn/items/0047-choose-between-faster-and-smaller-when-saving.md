---
id: 47
uid: bbfcea2b-502d-42ad-a397-e17707d8417b
title: Choose between Faster and Smaller when saving
type: feature
status: backlog
milestone: later
created: 2026-10-20
updated: 2026-11-01
priority: p3
effort: s
area: archive
---

## Problem

Every save uses the default deflate level.

## Proposal

A Faster / Smaller choice in the Duplicate and Save panels' accessory, remembered per archive.

## Acceptance criteria

- [ ] Smaller uses level 9 and Faster level 1, measured by the benchmarks

## 2026-11-01

Reconciled 2026-11-01 (0072). Settings > Compression (Faster, Balanced, Smaller) maps to levels 1, 6 and 9 and reaches writeZip and export; writeZipHonorsCompressionLevel checks the option is applied. The criterion asks for a benchmark measurement, which doesn't exist yet.
