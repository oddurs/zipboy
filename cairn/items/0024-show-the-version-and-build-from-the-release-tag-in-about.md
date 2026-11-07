---
id: 24
uid: 4082c34f-1f2e-447c-b883-05f7ef3c8cbc
title: Show the version and build from the release tag in About
type: feature
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p2
effort: s
area: shell
---

## Problem

The About window says 0.1.0 forever, because the version is hard-coded in Info.plist.

## Proposal

`scripts/task build` writes CFBundleShortVersionString from `git describe` and CFBundleVersion from the commit count.

## Acceptance criteria

- [x] A build on tag `v0.2.0` shows 0.2.0 in About
- [x] A build between tags shows the next version with a `-dev` suffix and the commit count as the build

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. scripts/task build stamps CFBundleShortVersionString from an exact tag (criterion 1). Criterion 2 is not met: between tags it stamps the previous tag plus -dev (0.1.0-dev after v0.1.0), not the next version.

## 2026-11-07

Extracted version_for_repo (and scripts/task version [repo]) so exact tags stamp their version (v0.2.0 -> 0.2.0), commits past a prerelease tag stamp its target version with -dev (v0.1.0-rc.1 -> 0.1.0-dev), commits past a release tag bump the patch and add -dev (v0.1.0 -> 0.1.1-dev, v0.2.0 -> 0.2.1-dev), and untagged repos stamp 0.1.0-dev, alongside git rev-list --count HEAD as CFBundleVersion. Simplified Updates.isNewer to pure SemVer comparison now that -dev stamps the next version instead of the previous tag. Covered by BundleTests.stampsReleaseTagsAndNextDevVersionsWithCommitCount and UpdatesTests.comparesVersions.

## Result

scripts/task stamps CFBundleShortVersionString with the exact release tag on tags and the next SemVer version plus -dev between tags, with the commit count as CFBundleVersion, and Updates.isNewer compares -dev versions directly by SemVer precedence.
