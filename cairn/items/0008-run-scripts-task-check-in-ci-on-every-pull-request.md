---
id: 8
uid: 0946f681-eff3-41ba-9f31-5c1271bbf55f
title: Run scripts/task check in CI on every pull request
type: chore
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
depends_on:
- 7
created: 2026-10-20
updated: 2026-10-20
closed_at: 2026-10-20
priority: p0
effort: s
area: quality
---

## Problem

Nothing stops a change that breaks the build or the suite from merging.

## Proposal

A GitHub Actions workflow on the macOS 15 runner that calls `scripts/task check` and nothing else, so CI and the hooks cannot drift.

## Acceptance criteria

- [x] The workflow runs on every pull request and on pushes to `main`
- [x] It invokes only `scripts/task check`
- [ ] Branch protection requires it to pass before merging
- [x] A deliberately failing test on a branch turns the check red

## 2026-10-20

Evidence: PR #2 run 39532760568 ran scripts/task check on macos-26 (Swift 6.3.3): format, lint, 29 tests, universal build, then 'required' passed. Throwaway PR #3 added a failing test; run 39532922609 failed 'deliberatelyFails() ... 1 == 2' and skipped 'required'. Requiring the check before merge needs branch protection, which this private repo can't have on the free plan; that is item 53.

## Result

CI runs scripts/task check on macos-26 for every PR and push to main; the 'required' job is the one status to protect once item 53 is unblocked.
