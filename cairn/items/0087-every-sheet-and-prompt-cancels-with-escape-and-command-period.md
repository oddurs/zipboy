---
id: 87
uid: 28f4d9c8-7a60-4d61-9545-dc25e528896c
title: Every sheet and prompt cancels with Escape and Command-period
type: bug
status: backlog
milestone: v0.2
created: 2026-11-02
updated: 2026-11-02
priority: p2
effort: s
area: shell
---

## Problem

The custom prompts in `Prompts.swift` (password, conflicts, new password) may lack a Cancel
button with the Escape key equivalent, which is how every Mac sheet is dismissed from the keyboard.

## Proposal

Give each prompt's Cancel button `keyEquivalent = "\u{1b}"`, which AppKit also binds to ⌘., and
make sure cancelling resolves to the "nothing happened" path rather than an error.

## Acceptance criteria

- [ ] Each prompt has a Cancel button whose key equivalent is Escape, covered by a test per prompt
- [ ] Cancelling the password prompt leaves the archive closed with no error alert
