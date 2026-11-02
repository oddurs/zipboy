---
id: 46
uid: 374a8530-0524-4649-a085-1ac5e1ef50a5
title: What would the Mac App Store's sandbox break?
type: spike
status: done
milestone: later
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-11-02
priority: p3
effort: s
area: distribution
---

## Question

What would the Mac App Store's sandbox break: writing next to the archive, temporary workspaces,
Services, the Quick Look extension? What would each fix cost?

## Why it matters

The App Store would reach more people, but only if the app keeps working the way it does now.

## Timebox

Half a day, when there is a reason to do it.

## Answer

Not now. The sandbox breaks the one default Zipboy is built around, writing next to the archive,
and the fix costs more than the App Store would return before v1.0. Distribution stays Developer ID
and notarized (0058). Audit of the code as of 2026-11-02:

- **Breaks: writing beside the archive.** Opening a file grants access to that file, not its folder.
  Extract with the default "Next to the archive" destination, the Finder service's Compress with
  Zipboy (writes the ZIP beside the selection) and Extract Here all write into a folder nobody granted.
  Fix: ask for the folder once with an open panel and keep a security-scoped bookmark per folder,
  or change the default to Downloads (`files.downloads.read-write`). Filed as 0088, deferred.
- **Probably breaks: becoming the default app.** `NSWorkspace.setDefaultApplication` from a sandboxed
  app is untested here, and App Review discourages prompting for it. Would need checking.
- **Works as is.** The workspace lives in `FileManager.temporaryDirectory`, which becomes the
  container's tmp, on the same volume, so clones still work. Saving goes through NSDocument, which
  the sandbox grants. Extract To… uses an open panel, which grants the folder. Reveal in Finder, Open
  With, the Keychain, drag out, and nested archives (in the container) need nothing. Both Quick Look
  extensions are already sandboxed.
- **Needs an entitlement only.** `files.user-selected.read-write` for panels; `network.client` once
  the update check (0033) exists, though the App Store would replace that check entirely.

Cost to ship to the App Store: 0088 (m), testing every Finder-service and extract path sandboxed,
dropping the update check from that build, and a second signing identity. Revisit after v1.0 if
people ask for it there.
