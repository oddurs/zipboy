---
id: 74
uid: f0196c75-bbc5-4837-8f07-7d4484a4fb57
title: Move timing budgets out of the unit suite
type: chore
status: backlog
milestone: v0.2
created: 2026-11-01
updated: 2026-11-01
priority: p2
effort: s
area: quality
---

## Problem

`BenchmarkBudgetTests` asserts wall-clock budgets (250 ms catalog, 500 ms delta save) inside the
ordinary test suite, so `scripts/task check` and CI can fail on a busy machine for reasons that aren't
bugs. `scripts/bench` only re-runs the same test.

## Proposal

Take the timing assertions out of `swift test`, and have `scripts/bench` build and run the
measurements itself, printing each against its budget, as 0022 describes.

## Acceptance criteria

- [ ] The unit suite asserts no wall-clock durations
- [ ] `scripts/bench` prints each measurement beside its budget and exits non-zero when one is 20% over
