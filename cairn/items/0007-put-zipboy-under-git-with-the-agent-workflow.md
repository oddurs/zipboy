---
id: 7
uid: fbbf16f6-8c36-4b0f-89ca-7dc3aaff3a28
title: Put Zipboy under git with the agent workflow
type: chore
status: backlog
milestone: v0.1
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: s
area: quality
---

## Problem

The project has no repository, so there is no history, no review, and no way to tag a release.

## Proposal

Run the bootstrap-repo workflow: `git init`, a private GitHub repository, `scripts/agent`, the tracked hooks in `.githooks/`, and branch protection on `main`. The first commit is the code as it stands.

## Acceptance criteria

- [ ] `scripts/agent doctor` passes on a fresh clone
- [ ] The pre-commit hook runs `scripts/task fmt:check`; pre-push runs `scripts/task check`
- [ ] The commit-msg hook rejects tool attribution trailers
- [ ] `main` refuses direct pushes; changes land only through a merged pull request
