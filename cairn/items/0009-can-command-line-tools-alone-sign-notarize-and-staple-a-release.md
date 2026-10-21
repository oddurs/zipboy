---
id: 9
uid: a1acee08-6c56-4ed5-960e-241ff60de4e9
title: Can Command Line Tools alone sign, notarize, and staple a release?
type: spike
status: backlog
milestone: v0.1
created: 2026-10-20
updated: 2026-10-20
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
