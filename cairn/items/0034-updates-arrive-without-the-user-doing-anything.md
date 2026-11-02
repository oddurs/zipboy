---
id: 34
uid: f93b2186-e25c-4100-85c2-85324150d97c
title: Updates arrive without the user doing anything
type: feature
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
depends_on:
- 10
- 33
created: 2026-10-20
updated: 2026-11-02
priority: p1
effort: m
area: distribution
---

## Problem

An installed Zipboy never learns there is a newer one.

## Proposal

Implement what the updates spike decided: check daily, download in the background, verify the signature, and offer to restart once, quietly.

## Acceptance criteria

- [x] An installed v0.4.0 offers v0.4.1 within a day of its release
- [x] An update with a bad signature is refused and logged
- [x] Updating never interrupts an unsaved document

## 2026-11-02

Evidence. UpdatesTests: release parsing (prereleases and incomplete releases ignored), ten version comparisons including rc and -dev, checksum match and mismatch. UpdaterTests: an automatic check offers a newer release, then stays quiet within the day and for the same version later; a manual check always answers; turned off in Settings it waits to be asked; a download whose SHA-256 doesn't match is deleted, logged (os_log, subsystem com.oddurs.zipboy, category updates), and refused. Criterion 2 reads 'bad signature' and is met as a bad checksum: integrity, not authenticity, until 0058 gives a Developer ID to check (see 0033's answer). Criterion 3 holds by design: the updater never quits or replaces the app. Not exercised against the real GitHub API (only an rc prerelease exists, which the latest-release endpoint skips).
