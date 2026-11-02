---
id: 66
uid: 4729d891-3e5b-4a81-9b1c-82e7794a1f93
title: Readable errors, hostile archive guards, Keychain passwords, spring-loaded folders, version stamping, and Help guide
type: feature
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p0
effort: l
area: archive
---

## Problem

1. Failures still surface raw `libarchive` or POSIX error strings directly without translating them into human-readable explanations and next steps (`0023`), and decompression bombs (extreme compression ratios or entry counts) need explicit ratio/entry-count guards (`0041`).
2. Reopening a password-protected archive prompts for the password every time because passwords are not optionally remembered in the macOS Keychain (`0039`).
3. Hovering a dragged file over a collapsed folder in the browser does not spring-load (expand) the folder (`0037`).
4. The Help menu is empty (`0042`), `scripts/task build` does not stamp `CFBundleShortVersionString` / `CFBundleVersion` from git tags/commits (`0024`), and Zipboy never offers once on the third launch to become the default ZIP handler (`0038`).

## Proposal

- Add human-readable error mapping (`ArchiveError.describe(_:fileName:)`) in `ZipboyKit` with actionable recovery suggestions and an expandable technical details disclosure in `Prompts`.
- Add hostile archive decompression-bomb guards (max entry count, max compression ratio for large payloads, and declared-vs-actual size checks) in `Archive.swift`.
- Add `Keychain` (`Sources/Zipboy/Keychain.swift`) and a "Remember password in Keychain" checkbox in `Prompts`, automatically looking up saved passwords on open and removing them on `removePassword`.
- Add spring-loaded folder expansion (0.7 s hover during drag) in `BrowserViewController`.
- Add offline `Help.html` guide and **Help > Zipboy Help** (`⌘?`) window, third-launch default-handler offer, git version stamping in `scripts/task`, and `scripts/bench` performance budget runner.

## Acceptance criteria

- [x] `ArchiveError.describe(_:fileName:)` maps truncated, corrupt, unsupported, permission-denied, disk-full, and bomb errors to clear user-facing sentences with unit tests
- [x] Decompression bomb guards refuse extreme compression ratios and entry counts before exceeding limits
- [x] Keychain password storage saves, retrieves, and deletes archive passwords with unit tests
- [x] Hovering a drag over a collapsed folder for 0.7 s expands it, and **Help > Zipboy Help** opens the offline guide
- [x] `scripts/task build` stamps version/build from git and `scripts/bench` measures catalog listing, delta save, and extraction budgets

## 2026-11-01

Overlaps 0022, 0023, 0024, 0037, 0038, 0039, 0041, 0042. Follow-ups from review: 0069 (bomb guards), 0070 (Keychain keyed by inode).
