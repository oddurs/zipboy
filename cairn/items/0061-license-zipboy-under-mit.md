---
id: 61
uid: 0f69380b-0996-4bc8-add9-653e7e2fea01
title: License Zipboy under MIT
type: docs
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-24
updated: 2026-10-24
closed_at: 2026-10-24
priority: p1
effort: s
area: distribution
---

## Problem

The repository is public but has no license, so legally nobody may use, change, or share the code.

## Proposal

The MIT License, as in the owner's other projects, with a License section in the README.

## Acceptance criteria

- [x] `LICENSE` holds the MIT text with "Copyright (c) 2026 Oddur Sigurdsson"
- [x] GitHub detects the license as MIT
- [x] The README says how Zipboy is licensed and that the vendored test fixtures keep their own licenses

## 2026-10-24

LICENSE is common-shot's MIT text, 'Copyright (c) 2026 Oddur Sigurdsson'; the README has a License section crediting the fixtures' own licenses. GitHub's license detection only reads the default branch (the API answers 404 for this branch), so criterion 2 is checked after merge.

## 2026-10-24

After merging #18, GitHub's license API for the repository answers 'MIT MIT License LICENSE'.

## Result

Zipboy is MIT licensed, and GitHub shows it.
