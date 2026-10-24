---
id: 10
uid: 190e2d49-c4bf-417d-8ae0-6e9843d60bd4
title: 'Release workflow: a tag produces a DMG on GitHub Releases'
type: feature
status: backlog
milestone: v0.1
depends_on:
- 8
created: 2026-10-20
updated: 2026-10-23
priority: p0
effort: m
area: distribution
---

## Problem

There is no way to get Zipboy onto someone else's Mac.

## Proposal

A workflow on `v*` tags that runs `scripts/task build`, wraps the app in a DMG with an Applications link,
and attaches it with a checksum to a GitHub release whose notes are the changelog section. Signing with a
Developer ID and notarizing are 0058, which waits on the certificate (see 0009's answer); until then the
app is ad hoc signed and the release notes say how to open it.

## Acceptance criteria

- [ ] Pushing a `v*` tag produces a release with `Zipboy-<version>.dmg` and its SHA-256 attached
- [ ] The DMG mounts with `Zipboy.app` and an Applications link, and the app in it launches
- [ ] CFBundleShortVersionString and CFBundleVersion come from the tag
- [ ] The release notes explain how to open an app that isn't notarized yet
- [ ] The workflow can be run by hand on a branch without publishing anything, for testing
