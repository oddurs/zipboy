---
paths:
  - "Sources/Zipboy/**"
  - "Resources/Info.plist"
---

# The app shell

- `ArchiveDocument` autosaves in place. `read(from:)` only records the URL; unpacking runs off the main
  thread after the window opens, so password prompts are sheets. Never do the work in `read`.
- Saving snapshots the workspace with `clonefile` in `save(to:…)` on the main thread, then
  `write(to:)` zips the snapshot in the background after `unblockUserInteraction()`. Any edit calls
  `editsInvalidateAutosave()` so a stale autosave cancels with `userCancelled`.
- Every edit is a list of `Move`s inside the workspace, registered for undo by `perform(_:named:)`.
  New edits go through it so undo, redo, and autosave cancellation keep working.
- A format that can't be written (RAR, 7z, tar) opens as an untitled ZIP (`importedFrom`). Never give
  it the original's `fileURL`: autosave would replace the RAR with a ZIP. `DocumentTests` guards this.
- NSDocument is `@MainActor` but AppKit calls `read`/`write` off it: keep them `nonisolated` and reach
  main state through `onMain` or `Locked`. QuickLook conformances need `@preconcurrency`.
- `AppDelegate.application(_:open:)` routes non-archives into a new archive (Dock drops); the catch-all
  document type in Info.plist has no class and rank None. `BundleTests` checks the plist.
- The menu bar is code (`MainMenu`): Command Line Tools can't compile nibs. AppKit adds Open Recent,
  Close All, and Share itself; don't add them again.
