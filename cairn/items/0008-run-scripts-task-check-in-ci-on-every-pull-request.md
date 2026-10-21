---
id: 8
uid: 0946f681-eff3-41ba-9f31-5c1271bbf55f
title: Run scripts/task check in CI on every pull request
type: chore
status: backlog
milestone: v0.1
depends_on:
- 7
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: s
area: quality
---

## Problem

Nothing stops a change that breaks the build or the suite from merging.

## Proposal

A GitHub Actions workflow on the macOS 15 runner that calls `scripts/task check` and nothing else, so CI and the hooks cannot drift.

## Acceptance criteria

- [ ] The workflow runs on every pull request and on pushes to `main`
- [ ] It invokes only `scripts/task check`
- [ ] Branch protection requires it to pass before merging
- [ ] A deliberately failing test on a branch turns the check red
