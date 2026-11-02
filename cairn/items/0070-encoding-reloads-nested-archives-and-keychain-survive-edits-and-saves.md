---
id: 70
uid: d320a698-2547-4e76-a53a-bcd3c2e9ba23
title: Encoding reloads, nested archives, and Keychain survive edits and saves
type: bug
status: done
milestone: v0.2
assignee: Oddur Sigurdsson
created: 2026-11-01
updated: 2026-11-01
closed_at: 2026-11-01
priority: p1
area: document
effort: m
---

## Problem

Three lifecycle paths in `ArchiveDocument` lose data or state:

- View > Text Encoding re-extracts the source and replaces the workspace, so unsaved edits and the
  undo stack vanish without a word. And `importedFrom` is never cleared, so once a RAR or tarball has
  been saved as a ZIP, re-reading names opens that ZIP as an import and sets `fileURL` to nil: the
  document is detached from its own file.
- Remembered passwords are keyed by inode. Every save renames a new file into place, so the next open
  prompts again and the old Keychain item stays forever. `setPassword`'s result is thrown away, so a
  failure to store is silent.
- Closing an archive deletes its workspace while a nested archive opened from it is still open. The
  child's file is in that workspace, so its edits never reach the parent and its next save targets a
  deleted path.

## Proposal

- Re-reading names asks first, as a sheet, when there are unsaved changes, and is unavailable while a
  save is running. A confirmed re-read leaves the document clean. Saving an imported document as a
  ZIP clears `importedFrom`; until then it never gets the original's `fileURL`.
- Key Keychain items by the archive's resolved path, which saves keep. When the document's file moves
  while open, carry the item to the new path. `setPassword` throws, and the failure is shown on the
  window where it happened.
- A parent tracks the nested documents opened from it. Closing it first asks each child to close,
  which autosaves the child into the parent's workspace (or asks, for an untitled child), and only
  then closes itself, saving what the children wrote.

## Acceptance criteria

- [x] Choosing a text encoding with unsaved edits asks first; declining keeps the edits, the undo stack, and the encoding (`DocumentLifecycleTests`)
- [x] Re-reading names without unsaved edits asks nothing, and a confirmed re-read leaves the document unedited
- [x] An imported archive saved as a ZIP has `importedFrom` cleared, and re-reading names keeps its `fileURL`
- [x] A remembered password is found after the archive is replaced at its path, as a save does
- [x] A remembered password follows the document's file when it moves while open
- [x] `Keychain.setPassword` throws on failure, and both callers show the error instead of discarding it
- [x] Closing a parent saves an edited nested child into it first, and the parent's saved ZIP holds the child's edit
- [x] `scripts/task check` passes

## 2026-11-01

Regression tests in Tests/ZipboyTests/DocumentLifecycleTests.swift fail on unfixed main (6 issues): reReadingNamesWithUnsavedEditsAsksFirst -> tree.find("untitled folder") nil after reload(withEncoding:) (edit discarded unasked). anImportSavedAsAZipKeepsItsFileWhenNamesAreReRead -> importedFrom still (container.rar, RAR) after Save As, and after re-reading fileURL nil, importedFrom (container.zip, ZIP). aRememberedPasswordSurvivesSavingInPlace -> Keychain.password nil after renaming a new file over the archive. closingAParentSavesTheNestedArchiveOpenFromItFirst -> nested.zip in the saved parent lacks the child's 'untitled folder': finding 9 confirmed, the child's edit never reaches the parent.

## 2026-11-01

NSDocument counts an undo-group edit on a later turn of the main queue, so isDocumentEdited is false immediately after the edit in a test; the test edit helper waits for it.

## 2026-11-01

Keychain keyed by the archive's path (folder symlinks resolved). Weighed against a UUID extended attribute: an xattr survives a Finder rename while closed, but it writes to the user's file (and to originals we promise never to touch), NSDocument's safe-save replacement isn't documented to carry custom xattrs so it would need re-stamping on every save (the same fragility as the inode), and it rides along with copies. The path survives every save by construction; moves while open are handled by presentedItemDidMove and move(to:). Cost: renaming the archive in Finder while it is closed orphans the item and the next open asks again. aRememberedPasswordMovesWithItsArchive fails with the move hook disabled (3 issues) and passes with it.

## 2026-11-01

Finding 9 handled in canClose rather than close(): close() runs after the decision, and saving is asynchronous. The parent asks each nested document to close first (NSDocument's own canClose, so a child with a file autosaves into the parent's workspace and an untitled child asks), then answers for itself, so the parent's save includes the child's. A child that refuses keeps the parent open. Encoding: re-reading asks as a sheet only when isDocumentEdited, and is unavailable while a save is running; a confirmed re-read clears the change count. The undo stack still goes on every re-read, as with Revert. Keychain.setPassword failures are presented by unpack, choosePassword, and the move hooks; checked by build and reading, not by a test, since a Keychain write failure can't be provoked in a test.

## 2026-11-01

After the fixes: DocumentLifecycleTests 5/5 pass; scripts/task check passes, 72 tests in 14 suites.

## Result

Re-reading names asks as a sheet before discarding unsaved edits, and an import saved as a ZIP drops importedFrom so it keeps its file. Keychain items are keyed by the archive's path, which saves keep, and move with an open archive; a failure to store is shown. Closing a parent closes, and so saves, its nested archives first. Weak spot: renaming an archive in Finder while it is closed still orphans its Keychain item. Tests: DocumentLifecycleTests.
