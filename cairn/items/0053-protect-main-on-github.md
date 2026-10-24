---
id: 53
uid: 95521d4d-4ca7-441e-90c2-93d3658b1519
title: Protect main on GitHub
type: chore
status: done
milestone: v0.1
depends_on:
- 7
created: 2026-10-20
updated: 2026-10-24
closed_at: 2026-10-24
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

- [x] `gh api repos/oddurs/zipboy/branches/main/protection` shows pull requests and the `required` check enforced
- [x] A direct `git push --no-verify origin HEAD:main` from a scratch branch is rejected by GitHub

## Proposed status: blocked -> planned (Oddur Sigurdsson, 2026-10-20)

Needs the owner's decision: make oddurs/zipboy public, or upgrade to GitHub Pro, so branch protection is available on it.

## 2026-10-24

Done on 2026-10-24 after the owner asked for the repository to be public. GitHub reads back: required checks ['required'] with strict up-to-date, PR required (0 approvals, solo repo), enforce_admins true, linear history, conversation resolution, no force pushes or deletions; squash-only merges, branches deleted on merge, auto-merge allowed. A direct commit to main through the contents API was refused: 'Changes must be made through a pull request. Required status check "required" is expected.' (HTTP 409). That is the server-side form of criterion 2; pushing with --no-verify is never done here.

## Result

main is protected on GitHub: PRs only, 'required' check, admins included.

## Accepted status: planned (Oddur Sigurdsson, 2026-10-24)

Proposed by Oddur Sigurdsson on 2026-10-20.
