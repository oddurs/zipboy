---
paths:
  - "Sources/ZipboyQuickLook/**"
  - "Resources/QuickLook/**"
---

# The Quick Look extensions

- Two app extensions: `ZipboyQuickLook` (Space-bar preview) and `ZipboyThumbnail` (Finder's icon). Each
  is built by SwiftPM as an executable whose entry point is `NSExtensionMain` (`Package.swift`),
  assembled into `Contents/PlugIns/<name>.appex` with its plist from `Resources/<name minus Zipboy>/`,
  and signed with `Resources/QuickLook/QuickLook.entitlements` before the app, by `scripts/task build`.
- It runs sandboxed inside Finder's Quick Look, so it lists and never unpacks: `Archive.list` and
  `ArchivePreview.html`, and `Archive.firstImage` in ZipboyKit, where they are tested. Keep the
  extensions thin wrappers, and never ask for or try a password.
- `NSExtensionPrincipalClass` names the provider's `@objc` name; `BundleTests` checks it, and that every
  previewed type is one the app opens.
- To try a change, register the built app (`lsregister -f -R build/Zipboy.app`), press Space on an
  archive, and read `log show --last 5m --predicate 'subsystem == "com.oddurs.zipboy.quicklook"'`, which
  records every preview and how long it took. For thumbnails, ask `QLThumbnailGenerator` for one and
  save its `cgImage`, which needs no screen. `qlmanage -p -o` crashes on app extensions and `qlmanage -t`
  hangs; don't trust either.
