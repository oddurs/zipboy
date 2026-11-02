---
id: 22
uid: b8de3f60-aa3e-4165-bdcb-7e8e3b6d6138
title: Benchmarks with budgets for opening, listing, and saving
type: feature
status: backlog
milestone: v0.2
depends_on:
- 21
created: 2026-10-20
updated: 2026-11-01
priority: p1
effort: m
area: quality
---

## Problem

Performance claims in the milestones have nothing measuring them, so they will rot.

## Proposal

`scripts/bench` generates large archives once (5 GB, and 100,000 small entries), times open, list, one-file save, and full save, and compares with budgets in a checked-in file. CI runs it nightly.

## Acceptance criteria

- [ ] `scripts/bench` prints each measurement against its budget
- [ ] It exits non-zero when any measurement is 20% over budget
- [ ] A nightly CI job runs it and keeps the results as an artifact

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. scripts/bench exists but only runs BenchmarkBudgetTests (ArchiveTests.swift), a timing test that also runs in the ordinary suite: wall-clock budgets there can flake on a loaded CI runner. None of the three criteria hold as written: it doesn't print measurements against budgets, a failure is a test failure rather than an exit on 20% over, and there is no nightly job.
