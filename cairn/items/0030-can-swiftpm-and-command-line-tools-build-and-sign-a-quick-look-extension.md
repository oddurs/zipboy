---
id: 30
uid: a44f81d5-f314-4d79-bb7f-d0dd9167e587
title: Can SwiftPM and Command Line Tools build and sign a Quick Look extension?
type: spike
status: backlog
milestone: v0.4
created: 2026-10-20
updated: 2026-10-20
priority: p0
effort: s
area: system
---

## Question

A Quick Look preview extension is an `.appex` bundle inside the app. Can we build its Mach-O with SwiftPM, lay out the bundle by hand, sign it with the right entitlements, and have `pluginkit` load it, all without Xcode?

## Why it matters

Finder previews of archives are the most visible integration, and the build system is the unknown.

## Timebox

One day. The answer is a working hello-world extension, or a decision to require Xcode for this target.

## Answer
