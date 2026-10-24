---
name: run-app
description: Launch Zipboy from a build, open archives in it, and screenshot its windows in light or dark mode for visual review or the README. Use when asked to run, try, look at, or screenshot the app, or to check a UI change on screen.
---

# Run and look at Zipboy

1. Build: `scripts/task build` (release, at `build/Zipboy.app`), or `swift build` and copy
   `.build/debug/Zipboy` into a bundle with `Resources/Info.plist` for a faster debug run.
2. Quit other copies first; LaunchServices sends `open` to a running Zipboy with the same bundle id:
   `pkill -x Zipboy`.
3. Launch without restoring last session's windows:
   `open -n -a build/Zipboy.app --args -ApplePersistenceIgnoreState YES`.
   Add `-NSRequiresAquaSystemAppearance YES` to force light mode on a dark Mac.
4. Open an archive: `open -a build/Zipboy.app path/to/archive.zip`. Fixtures in
   `Tests/ZipboyKitTests/Fixtures/matrix` are handy.
5. Screenshot one window, never the whole screen (it shows whatever else the person has open):
   `swiftc .claude/skills/run-app/winid.swift -o /tmp/winid` once, then
   `screencapture -o -l "$(/tmp/winid Zipboy | head -1 | cut -d' ' -f1)" shot.png`.
6. Keystrokes go to whatever is frontmost, which may be the person's own work. Send them only through
   System Events after checking Zipboy is in front, and never move the mouse on a Mac someone may be
   using.
7. Look at every screenshot before calling a UI change done.

Gotchas: Foundation ignores `TMPDIR`, so the app can't be pointed at a different workspace disk. A
window that never appears usually means another Zipboy took the `open`.
