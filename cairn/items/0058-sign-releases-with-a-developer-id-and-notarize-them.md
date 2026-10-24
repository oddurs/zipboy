---
id: 58
uid: b47e1d98-3759-4821-a1e1-bef5be795b9b
title: Sign releases with a Developer ID and notarize them
type: feature
status: blocked
milestone: v0.1
depends_on:
- 9
- 10
created: 2026-10-23
updated: 2026-10-23
priority: p0
effort: s
area: distribution
---

## Problem

Releases are ad hoc signed, so Gatekeeper rejects them on any other Mac (`spctl` says `rejected`), and a
user has to know to right-click and Open, or go to Privacy & Security.

## Proposal

In the release workflow, when the signing secrets exist: import the Developer ID certificate into a
temporary keychain, sign the app and DMG with it and the hardened runtime, submit the DMG with
`xcrun notarytool submit --wait` using the API key, and `xcrun stapler staple` both.

## Acceptance criteria

- [ ] `spctl --assess --type open --context context:primary-signature` accepts the released DMG
- [ ] `xcrun stapler validate` passes on the DMG and on the app inside it
- [ ] On a clean user account, the downloaded app opens with only the standard "downloaded from the internet" prompt
- [ ] The secrets never appear in logs, and the temporary keychain is deleted at the end of the job

## 2026-10-23

Blocked on the owner: needs Apple Developer Program membership, a Developer ID Application certificate (.p12 and password), and an App Store Connect API key, added as repository secrets. See 0009's answer.
