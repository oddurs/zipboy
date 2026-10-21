---
id: 10
uid: 190e2d49-c4bf-417d-8ae0-6e9843d60bd4
title: 'Release workflow: a tag produces a notarized DMG on GitHub Releases'
type: feature
status: backlog
milestone: v0.1
depends_on:
- 8
- 9
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: m
area: distribution
---

## Problem

There is no way to get Zipboy onto someone else's Mac.

## Proposal

A workflow on `v*` tags that runs `scripts/task build`, signs with the Developer ID from repository secrets, wraps the app in a DMG with an Applications link, notarizes, staples, and attaches it to a GitHub release with the changelog section as notes.

## Acceptance criteria

- [ ] Pushing `v0.1.0` produces a release with `Zipboy-0.1.0.dmg` attached
- [ ] `spctl --assess --type open --context context:primary-signature` accepts the DMG
- [ ] `xcrun stapler validate` passes on both the DMG and the app
- [ ] On a clean user account, the downloaded app opens with no Gatekeeper prompt beyond the standard one
- [ ] CFBundleShortVersionString and CFBundleVersion come from the tag
