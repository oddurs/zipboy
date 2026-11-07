---
id: 90
uid: 86d84b83-5be4-4d6c-9040-299c706dd960
title: Extracted files keep the quarantine mark of the archive they came from
type: bug
status: backlog
milestone: v0.1
created: 2026-11-06
updated: 2026-11-06
priority: p0
effort: s
area: archive
---

## Problem

macOS marks a downloaded file with the `com.apple.quarantine` attribute, and Gatekeeper checks marked
files before they run. Archive Utility copies the mark from an archive onto everything it unpacks.
Nothing in Zipboy's source handles the attribute, and `Info.plist` doesn't set
`LSFileQuarantineEnabled`, so an app inside a downloaded ZIP probably comes out unmarked and skips
that check. Found by reading the code on 2026-11-06, not yet reproduced.

## Proposal

Start with a test that reproduces it. Then, in `Archive.extract` in ZipboyKit, read the attribute from
the archive with `getxattr` and write it onto every item unpacked with `setxattr`. Doing it there covers
every caller: the workspace, the Finder services, and AppleScript. The copies that leave the workspace
(`FileCopy`, clones, drag out) keep extended attributes, which a test should confirm rather than assume.
Prefer this to `LSFileQuarantineEnabled`, which would also mark every ZIP Zipboy saves.

## Acceptance criteria

- [ ] A test extracts an archive carrying `com.apple.quarantine` and finds the attribute on every file and folder, and it fails without the fix
- [ ] An archive with no quarantine mark gives extracted files none
- [ ] The mark survives each way out of the app: Extract, Extract To…, the Extract Here service, AppleScript `extract`, and a file opened from the list
- [ ] A nested archive opened from a marked archive passes the mark to what it unpacks
