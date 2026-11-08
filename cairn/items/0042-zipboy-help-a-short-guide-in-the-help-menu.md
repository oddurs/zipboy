---
id: 42
uid: 2928a167-dd32-4b4d-b513-1d45b0f63519
title: 'Zipboy Help: a short guide in the Help menu'
type: docs
status: done
milestone: v1.0
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-11-07
closed_at: 2026-11-07
priority: p1
effort: m
area: distribution
---

## Problem

The Help menu is empty.

## Proposal

A small Apple Help Book, or a single bundled HTML page if the Help Book can't be built without Xcode, covering each README flow with one screenshot each.

## Acceptance criteria

- [x] Help > Zipboy Help opens the guide offline
- [x] Every README flow has a section
- [x] Searching Help for “password” finds the password section

## 2026-11-01

Reconciled 2026-11-01 (0072) against the batch merged as 0063-0066. Help > Zipboy Help (⌘?) opens an in-app, searchable guide (criterion 1). Criterion 3: helpWindowFiltersTopicsAndFindsPasswordSection. Criterion 2 not checked flow by flow against the README. The batch also shipped Resources/Help.html, which nothing loaded; 0072 removes it.

## 2026-11-02

2026-11-02: the Help Book that makes Help menu search find topics is 0084, which replaces the in-app help window once it works. This item keeps the content criterion (a section per README flow).

## 2026-11-07

Added dedicated Help sections for every README flow (open, edit, inplace, extract, create, import, password) alongside verify and export, and removed the unsupported Zstandard mention from the open section.

## Result

Every README flow has a dedicated section in HelpTopics and the Apple Help Book.
