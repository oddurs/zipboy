---
id: 102
uid: b1a257b8-30a4-42ff-8f5b-7553fcdd6ef8
title: Search inside the files in an archive
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: browser
---

## Problem

Search matches names only, so finding a phrase means extracting everything first.

## Proposal

Search scope in the search field: Names or Contents. The workspace is already unpacked, so Contents reads
text files there off the main thread, with a cap on file size, showing matches as they arrive. If lazy
unpacking (0027) lands first, this has to unpack as it goes.

## Acceptance criteria

- [ ] Searching contents for a phrase finds the text files holding it, covered by a test
- [ ] Binary files and files over the cap are passed over
- [ ] Typing a new search stops the one running
