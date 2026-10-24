---
id: 9
uid: a1acee08-6c56-4ed5-960e-241ff60de4e9
title: Can Command Line Tools alone sign, notarize, and staple a release?
type: spike
status: done
milestone: v0.1
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-10-23
closed_at: 2026-10-23
priority: p0
effort: s
area: distribution
---

## Question

With only Command Line Tools installed, can we sign with a Developer ID, submit with `notarytool`, and staple, locally and on a CI runner? Which entitlements does the hardened runtime need, if any?

## Why it matters

The release workflow depends on it, and a Mac that has never seen the app shows a Gatekeeper wall for anything ad hoc signed.

## Timebox

Half a day. Needs the owner's Developer ID certificate and an app-specific password or API key.

## Answer

Yes, with one missing piece: the certificate. Checked on macOS 26.5 with Command Line Tools only:

- `notarytool` 1.1.1 and `stapler` ship in `/Library/Developer/CommandLineTools/usr/bin`; no Xcode needed.
  GitHub's `macos-26` runner has them too.
- `scripts/task build` already signs with the hardened runtime (`flags=0x10002(adhoc,runtime)`), passes
  `codesign --verify --deep --strict`, and the app runs. No entitlements are needed: no JIT, no
  unsigned libraries, no Apple Events; libarchive is a system library.
- `spctl --assess --type execute build/Zipboy.app` says `rejected`, because the signature is ad hoc. Only a
  "Developer ID Application" certificate fixes that, and this Mac has none (its one identity is the
  self-signed "Common Tools Development").

What the owner has to provide, once: Apple Developer Program membership, a Developer ID Application
certificate exported as a .p12 with its password, and an App Store Connect API key (key id, issuer id,
.p8) for `notarytool`. In CI these become repository secrets.

So the release work splits: 0010 ships the DMG pipeline now, ad hoc signed, and 0058 adds Developer ID
signing and notarization once the certificate exists.

## Result

CLT is enough (notarytool, stapler; hardened runtime needs no entitlements). Missing: a Developer ID certificate and notary API key. Notarizing split into 0058, blocked on the owner.
