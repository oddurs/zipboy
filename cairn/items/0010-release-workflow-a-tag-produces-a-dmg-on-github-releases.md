---
id: 10
uid: 190e2d49-c4bf-417d-8ae0-6e9843d60bd4
title: 'Release workflow: a tag produces a DMG on GitHub Releases'
type: feature
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
depends_on:
- 8
created: 2026-10-20
updated: 2026-10-24
closed_at: 2026-10-24
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

- [x] Pushing a `v*` tag produces a release with `Zipboy-<version>.dmg` and its SHA-256 attached
- [x] The DMG mounts with `Zipboy.app` and an Applications link, and the app in it launches
- [x] CFBundleShortVersionString and CFBundleVersion come from the tag
- [x] The release notes explain how to open an app that isn't notarized yet
- [x] The workflow can be run by hand on a branch without publishing anything, for testing

## 2026-10-23

Local evidence: scripts/task package 0.1.0-test built the universal app, stamped CFBundleShortVersionString 0.1.0-test and CFBundleVersion 11 (commit count), re-signed (codesign --verify --deep --strict ok), and made build/Zipboy-0.1.0-test.dmg with Zipboy.app and an Applications link; the checksum file verifies with shasum -c, and the app launched from the mounted image. The workflow runs are checked after merge.

## 2026-10-24

Workflow evidence: pushing tag v0.1.0-rc.1 ran release.yml (run 40060269142, success) and published prerelease 'Zipboy 0.1.0-rc.1' with Zipboy-0.1.0-rc.1.dmg (1.3 MB) and its .sha256, notes opening with the 'Open Anyway' instructions. Downloaded with gh: shasum -c OK; the image holds Zipboy.app and an Applications link; version 0.1.0-rc.1, build 13; codesign --verify --deep --strict passes; the app launched from the mounted image. A workflow_dispatch run on main (40060241518, version 0.1.0-dryrun) kept the DMG as an artifact and published nothing; the release list holds only the rc.

## Result

Tags publish a DMG and checksum to GitHub Releases; v0.1.0-rc.1 is the first. Ad hoc signed until 0058.
