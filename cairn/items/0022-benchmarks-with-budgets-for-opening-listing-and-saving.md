---
id: 22
uid: b8de3f60-aa3e-4165-bdcb-7e8e3b6d6138
title: Benchmarks with budgets for opening, listing, and saving
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
depends_on:
- 21
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p1
effort: m
area: quality
---

## Problem

Performance claims in the milestones have nothing measuring them, so they will rot.

## Proposal

`scripts/bench` generates large archives once (5 GB, and 100,000 small entries), times open, list, one-file save, and full save, and compares with budgets in a checked-in file. CI runs it nightly.

## Acceptance criteria

- [x] `scripts/bench` prints each measurement against its budget
- [x] It exits non-zero when any measurement is 20% over budget
- [x] A nightly CI job runs it and keeps the results as an artifact

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. scripts/bench exists but only runs BenchmarkBudgetTests (ArchiveTests.swift), a timing test that also runs in the ordinary suite: wall-clock budgets there can flake on a loaded CI runner. None of the three criteria hold as written: it doesn't print measurements against budgets, a failure is a test failure rather than an exit on 20% over, and there is no nightly job.

## 2026-11-07

Added scripts/budgets.json, updated ZipboyBench and scripts/bench to generate/cache the 5 GB and 100k-entry fixtures, print each measurement against its budget, and exit non-zero when any measurement exceeds its budget by >20%. Added .github/workflows/bench.yml (nightly + workflow_dispatch with artifact upload) and BundleTests.benchPrintsMeasurementsExitsOverBudgetAndHasNightlyWorkflow. Measured on Apple Silicon: List 5 GB ZIP 0.1 ms (budget 100 ms), ZIP catalog 100k entries 23.5 ms (budget 200 ms), One-file save on 5 GB ZIP 3,799.5 ms (budget 6,000 ms), Open 5 GB ZIP 2,976.7 ms (budget 12,000 ms), Full save of 5 GB workspace 13,775.8 ms (budget 15,000 ms), CRC-32 + SHA-256 of 8 MB 3.3 ms (budget 300 ms), Quick Look preview 10k entries 34.4 ms (budget 300 ms).

## Result

scripts/bench times 5 GB and 100k-entry open, list, delta save, and full save against scripts/budgets.json, exits non-zero when >20% over budget, and runs nightly in .github/workflows/bench.yml.
