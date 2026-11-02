---
id: 87
uid: 28f4d9c8-7a60-4d61-9545-dc25e528896c
title: Every sheet and prompt cancels with Escape and Command-period
type: bug
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-02
updated: 2026-11-02
closed_at: 2026-11-02
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

- [x] Each prompt has a Cancel button whose key equivalent is Escape, covered by a test per prompt
- [x] Cancelling the password prompt leaves the archive closed with no error alert

## 2026-11-02

Evidence. NSAlert already gives a button titled Cancel the Escape key, so the password, new-password, and re-read prompts were fine; the conflict prompt's way out is Stop, which had no key. It now takes Escape, which AppKit also answers to Command-period. everyPromptCancelsWithEscape checks all four and fails with the fix removed. Criterion 2 by reading: a nil from the password prompt calls close() in ArchiveDocument with no alert; there is no seam to drive that open flow from a test.
