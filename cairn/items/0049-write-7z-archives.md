---
id: 49
uid: 6cdbb66c-22cf-4b53-a52e-64cd57d5c035
title: Write 7z archives
type: feature
status: backlog
milestone: later
created: 2026-10-20
updated: 2026-10-20
priority: p3
effort: l
area: archive
---

## Problem

Archives imported from 7z can only be saved as ZIP.

## Proposal

Use libarchive's 7z writer for documents that came from 7z, if users ask for it.

## Acceptance criteria

- [ ] A 7z opened, changed, and saved stays a 7z, readable by 7-Zip
