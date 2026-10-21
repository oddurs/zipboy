---
id: 7
uid: fbbf16f6-8c36-4b0f-89ca-7dc3aaff3a28
title: Put Zipboy under git with the agent workflow
type: chore
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-10-20
closed_at: 2026-10-20
priority: p0
effort: s
area: quality
---

## Problem

The project has no repository, so there is no history, no review, and no way to tag a release.

## Proposal

Run the bootstrap-repo workflow: `git init`, a private GitHub repository, `scripts/agent`, the tracked hooks in `.githooks/`, and branch protection on `main`. The first commit is the code as it stands.

## Acceptance criteria

- [x] `scripts/agent doctor` passes on a fresh clone
- [x] The pre-commit hook runs `scripts/task fmt:check`; pre-push runs `scripts/task check`
- [x] The commit-msg hook rejects tool attribution trailers
- [ ] `main` refuses direct pushes; changes land only through a merged pull request

## 2026-10-20

Evidence (2026-10-20): fresh clone of git@github.com:oddurs/zipboy.git, scripts/setup, then scripts/agent doctor printed '==> all good'. pre-commit runs scripts/task lint, which starts with fmt:check; pre-push runs scripts/task check and refused 'git push origin tmp/hook-probe:main' with 'refusing to push to main'. commit-msg rejected 'fixed stuff.' and a Co-Authored-By: Claude trailer. Criterion 4 holds only locally: GitHub answers branch protection on a private repo with 'Upgrade to GitHub Pro or make this repository public' (HTTP 403), so server-side protection moved to its own item, blocked on that decision.

## Result

Repo at github.com/oddurs/zipboy (private). Hooks: pre-commit lint, pre-push check and refuse main, commit-msg conventional and no attribution. Server-side protection is item 53, blocked on going public or Pro.
