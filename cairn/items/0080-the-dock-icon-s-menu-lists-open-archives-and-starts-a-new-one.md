---
id: 80
uid: 911f27bf-557f-4b1e-9aa6-b606d48c2f9b
title: The Dock icon's menu lists open archives and starts a new one
type: feature
status: backlog
milestone: v0.4
created: 2026-11-02
updated: 2026-11-02
priority: p3
effort: s
area: shell
---

## Problem

Right-clicking Zipboy in the Dock offers only the system's items. Document apps such as Preview
and TextEdit list their open windows there, and offer a new document.

## Proposal

`AppDelegate.applicationDockMenu(_:)` returns New Archive and Open…, then a separator. AppKit
adds the window list itself, so the menu must not repeat it.

## Acceptance criteria

- [ ] The Dock menu offers New Archive and Open…, each doing what the File menu item does, covered by a test
- [ ] Open windows appear once, from AppKit, not twice
