---
id: 106
uid: d4b77590-e4eb-4bac-8937-9dab92744248
title: Choose the compression method and see the size first
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: archive
---

## Problem

Settings offers Faster, Balanced, and Smaller, which covers most people. Export gives no say in the
method or solid mode for 7z, and no idea of the result's size until it's written.

## Proposal

An Options disclosure in the Export panel, with the method and solid mode where the format has them, and
an estimate from compressing a sample. Keep it out of the main window. Item 0047 covers the simple choice,
which looks already done in Settings; check it and close it first.

## Acceptance criteria

- [ ] Export can write a solid 7z, which Zipboy reads back
- [ ] The estimate lands within 25% of the real size on the benchmark archive
