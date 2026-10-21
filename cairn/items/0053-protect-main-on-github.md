---
id: 53
uid: 95521d4d-4ca7-441e-90c2-93d3658b1519
title: Protect main on GitHub
type: chore
status: blocked
milestone: v0.1
depends_on:
- 7
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: s
area: quality
---

## Problem

`main` is protected only by the local pre-push hook. A clone without `scripts/setup`, or a push from the
web UI, can still change `main` directly. GitHub refuses branch protection on a private repository on the
free plan (HTTP 403: "Upgrade to GitHub Pro or make this repository public").

## Proposal

Once the owner decides between making the repository public and upgrading to Pro, protect `main`: require
a pull request, require the `required` CI check, enforce for admins, forbid force pushes and deletion.

## Acceptance criteria

- [ ] `gh api repos/oddurs/zipboy/branches/main/protection` shows pull requests and the `required` check enforced
- [ ] A direct `git push --no-verify origin HEAD:main` from a scratch branch is rejected by GitHub

## Proposed status: blocked -> planned (Oddur Sigurdsson, 2026-10-20)

Needs the owner's decision: make oddurs/zipboy public, or upgrade to GitHub Pro, so branch protection is available on it.
