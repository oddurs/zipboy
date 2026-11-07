---
id: 90
uid: 86d84b83-5be4-4d6c-9040-299c706dd960
title: Extracted files keep the quarantine mark of the archive they came from
type: bug
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-11-06
updated: 2026-11-07
closed_at: 2026-11-07
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

- [x] A test extracts an archive carrying `com.apple.quarantine` and finds the attribute on every file and folder, and it fails without the fix
- [x] An archive with no quarantine mark gives extracted files none
- [x] The mark survives each way out of the app: Extract, Extract To…, the Extract Here service, AppleScript `extract`, and a file opened from the list
- [x] A nested archive opened from a marked archive passes the mark to what it unpacks

## 2026-11-07

Evidence. Reproduced before the fix: both ArchiveTests.propagatesQuarantineOntoEveryUnpackedItemAndLeavesUnmarkedArchivesClean and QuarantineTests.quarantineSurvivesEveryExitAndReachesNestedArchives failed with nil extended attributes on every unpacked path. Archive.extract now reads com.apple.quarantine from the archive with getxattr(..., XATTR_NOFOLLOW) and stamps every unpacked file, folder (explicit and implicit), hard link, and symlink under root before restoring folder dates; wrapped destination folders created by BrowserViewController.extract and AppDelegate.extractArchives copy it too. Testing FileCopy confirmed copyfile(3) rewrites the quarantine header flags/timestamp (0081 -> 0281) while keeping the quarantine event UUID intact.

## Result

Archive.extract and wrapped extraction folders preserve com.apple.quarantine across workspace opens, Extract, Extract To, Finder services, AppleScript, drag-out promises, and nested archives.
