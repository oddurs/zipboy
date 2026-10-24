---
id: 60
uid: 6ec53d13-47e4-434b-94ca-d1f8952e0327
title: Make the repository agent-native
type: chore
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-24
updated: 2026-10-24
closed_at: 2026-10-24
priority: p1
effort: m
area: quality
---

## Problem

The repository is public and protected, but it falls short of the agent-native standard: CLAUDE.md has
no workflow contract and carries path-specific notes every session; there are no path-scoped rules and no
skills for the procedures a newcomer gets wrong (releasing, regenerating fixtures, screenshotting the
app); the commit-msg hook rejects git's own Merge, Revert and fixup! messages; CI's actions aren't pinned
and it rebuilds from nothing every run.

## Proposal

Bring it to the standard the agentify workflow sets, without changing how anything builds.

## Acceptance criteria

- [x] CLAUDE.md ends with the workflow contract and keeps only what applies to every session
- [x] Path-specific guidance lives in `.claude/rules/` with `paths:` frontmatter
- [x] Skills exist for releasing, regenerating fixtures, and running the app for screenshots
- [x] commit-msg lets Merge, Revert, fixup!, squash! and amend! through, and still rejects attribution
- [x] CI's third-party actions are pinned to SHAs and SwiftPM's build is cached
- [x] `scripts/setup`, `scripts/agent doctor`, and `scripts/task check` pass; the PR goes through `scripts/agent pr`

## 2026-10-24

Done: CLAUDE.md now opens with commands and ends with the workflow contract; the architecture notes moved to .claude/rules/ (archive.md, app.md, testing.md, resources.md, each path-scoped); skills for release (manual only), fixtures, and run-app (with the window-id helper). scripts/task test takes an optional filter. commit-msg lets Merge, Revert, fixup!, squash!, amend! through and still rejects attribution (checked on sample messages, including an attributed squash!). CI pins checkout v7.0.1, upload-artifact v7.0.2 and cache v6.1.0 to SHAs and caches .build. scripts/setup, scripts/agent doctor and scripts/task check pass.

## Result

Agent-native: rules, skills, workflow contract, pinned and cached CI.
