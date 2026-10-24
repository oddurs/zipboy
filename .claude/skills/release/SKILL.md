---
name: release
description: Publish a Zipboy release — tag main, let the release workflow build and publish the DMG, and verify the download. Use when asked to cut, tag, publish, or ship a version or release candidate.
disable-model-invocation: true
---

# Release Zipboy

A tag on `main` is the release: `.github/workflows/release.yml` runs `scripts/task check`, then
`scripts/task package <version>`, and publishes the DMG and its `.sha256` with the notes in
`.github/release-notes.md` followed by GitHub's generated notes.

1. Make sure `main` is green: `gh run list --branch main --limit 1` shows `success` on the commit you
   mean to release, and `git status` is clean on an up-to-date `main`.
2. Pick the version. A hyphen makes a prerelease: `v0.2.0-rc.1`. Plain `v0.2.0` is a release.
3. To try the pipeline without publishing: `gh workflow run release.yml --ref main -f version=0.2.0-test`,
   then download the artifact from the run.
4. Tag and push from `main` (tags are allowed through the pre-push hook, which runs the full check):
   `git tag -a v0.2.0 -m "Zipboy 0.2.0" && git push origin v0.2.0`.
5. Wait for the run (`gh run list --workflow release.yml --limit 1`), then verify what users get:
   ```sh
   gh release download v0.2.0 -R oddurs/zipboy -D /tmp/zipboy-release
   cd /tmp/zipboy-release && shasum -a 256 -c Zipboy-*.dmg.sha256
   hdiutil attach Zipboy-*.dmg -nobrowse -readonly -mountpoint ./mnt
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" mnt/Zipboy.app/Contents/Info.plist
   codesign --verify --deep --strict mnt/Zipboy.app && hdiutil detach ./mnt
   ```
6. Report the release URL and each check's output.

Releases are ad hoc signed until item 0058 (Developer ID and notarization) lands, so users go through
Open Anyway once; the release notes say how. Don't promise otherwise.
