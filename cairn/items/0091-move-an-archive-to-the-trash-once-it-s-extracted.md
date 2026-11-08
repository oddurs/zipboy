---
id: 91
uid: c0789e14-ff02-4e25-86d8-2c7d0758e8ac
title: Move an archive to the Trash once it's extracted
type: feature
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
created: 2026-11-06
updated: 2026-11-07
closed_at: 2026-11-07
priority: p2
effort: s
area: shell
---

## Problem

Extracting a download leaves the archive behind, so Downloads fills with ZIPs nobody wants. Keka and
The Unarchiver both offer to clear them away.

## Proposal

A setting in Settings under Extract To: "After extracting: Keep the archive / Move it to the Trash",
defaulting to Keep. It applies to the Extract Here service and to extracting a whole archive from a window
with no unsaved changes. It uses `FileManager.trashItem`, never a delete, so the archive can be put back.

## Acceptance criteria

- [x] With the setting on, a successful Extract Here moves the archive to the Trash, covered by a test
- [x] A failed or stopped extract leaves the archive where it was
- [x] Extracting only some of the items never trashes the archive
- [x] An archive with unsaved edits is never trashed, and its window stays open

## 2026-11-07

Added Settings.AfterExtractBehavior (.keepArchive, .moveToTrash) and After Extracting pop-up in SettingsWindowController, wired to AppDelegate.extractArchives and BrowserViewController.extract for whole-archive extracts with no unsaved edits.

## Result

Optional 'Move it to the Trash' setting under Extract To moves extracted archives to the Trash via FileManager.trashItem while leaving failed, partial, or edited archives untouched.
