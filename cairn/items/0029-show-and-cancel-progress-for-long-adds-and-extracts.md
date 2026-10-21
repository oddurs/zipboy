---
id: 29
uid: 08f9080e-598a-4747-a3b6-de13eb3f3014
title: Show and cancel progress for long adds and extracts
type: feature
status: backlog
milestone: v0.3
created: 2026-10-20
updated: 2026-10-20
priority: p1
effort: m
area: shell
---

## Problem

Adding a large folder or extracting a large archive gives no sign of progress and can't be stopped.

## Proposal

Publish an `NSProgress` per operation, shown in the window's subtitle and, for extracts, on the destination file in Finder. Escape or the stop button cancels and cleans up.

## Acceptance criteria

- [ ] Operations longer than 1 second show progress in the subtitle
- [ ] Extracting shows Finder's progress pie on the destination
- [ ] Cancelling leaves neither partial files at the destination nor half-added items in the archive
