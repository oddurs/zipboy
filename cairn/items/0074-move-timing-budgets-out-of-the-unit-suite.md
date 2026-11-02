---
id: 74
uid: f0196c75-bbc5-4837-8f07-7d4484a4fb57
title: Move timing budgets out of the unit suite
type: chore
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-02
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

- [x] The unit suite asserts no wall-clock durations
- [x] `scripts/bench` prints each measurement beside its budget and exits non-zero when one is 20% over

## 2026-11-02

Evidence. BenchmarkBudgetTests and the 10,000-entry preview's time check are gone from the suite; the suite's only clocks now are deadlines that wait for something to happen. ZipboyBench (swift run -c release, via scripts/bench) measures the ZIP catalog, delta save, checksums, and the Quick Look preview of 10,000 entries, best of five, each beside its budget: 0.3, 9.9, 3.8, and 47.7 ms on this Mac. A budget forced to 0.0001 ms made it exit 1. The delta-save budget had failed a push at 994 ms while the suite ran in parallel; alone and in release it takes 10 ms.
