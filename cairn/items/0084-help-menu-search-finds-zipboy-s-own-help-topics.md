---
id: 84
uid: a6cf3b9a-26d6-48dc-8dc0-659b63059cbb
title: Help menu search finds Zipboy's own help topics
type: feature
status: backlog
milestone: v1.0
created: 2026-11-02
updated: 2026-11-02
priority: p2
effort: m
area: distribution
---

## Problem

Help > Zipboy Help opens an in-app window. Typing in the Help menu's search field finds menu items
but none of Zipboy's help topics, because there is no Apple Help Book for the system to index.

## Proposal

Build a Help Book from the same section text the help window shows: `Zipboy.help` with one HTML
page per section, indexed with `hiutil` (it ships with macOS), registered via `CFBundleHelpBookFolder`
and `CFBundleHelpBookName`. Help > Zipboy Help then opens Help Viewer. The in-app window goes once
the book works, so there is one help, not two.

## Acceptance criteria

- [ ] `scripts/task build` produces `Contents/Resources/Zipboy.help` with an index `hiutil -I` reads
- [ ] Typing "password" in the Help menu's search field lists the password topic, checked on screen
- [ ] The book's pages are generated from one source, and a test fails if a section lacks a page
