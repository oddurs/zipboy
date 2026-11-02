---
paths:
  - "Sources/ZipboyQuickLook/**"
  - "Resources/QuickLook/**"
---

# The Quick Look extension

- An app extension, built by SwiftPM as an executable whose entry point is `NSExtensionMain`
  (`Package.swift`), assembled into `Contents/PlugIns/ZipboyQuickLook.appex` and signed with
  `Resources/QuickLook/QuickLook.entitlements` before the app, by `scripts/task build`.
- It runs sandboxed inside Finder's Quick Look, so it lists and never unpacks: `Archive.list` and
  `ArchivePreview.html` in ZipboyKit, where they are tested. Keep the extension itself a thin wrapper.
- `NSExtensionPrincipalClass` names the provider's `@objc` name; `BundleTests` checks it, and that every
  previewed type is one the app opens.
- To try a change, register the built app (`lsregister -f -R build/Zipboy.app`), press Space on an
  archive, and read `log show --last 5m --predicate 'subsystem == "com.oddurs.zipboy.quicklook"'`, which
  records every preview and how long it took. `qlmanage -p -o` crashes on app extensions; don't trust it.
