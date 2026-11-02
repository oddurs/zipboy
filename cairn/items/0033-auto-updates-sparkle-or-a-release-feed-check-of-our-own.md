---
id: 33
uid: fd6e7f40-34e8-4043-9429-01d9cb953dc9
title: 'Auto-updates: Sparkle, or a release-feed check of our own?'
type: spike
status: done
milestone: v0.4
assignee: Oddur Sigurdsson
created: 2026-10-20
updated: 2026-11-02
priority: p1
effort: s
area: distribution
---

## Question

Sparkle is the standard but is a dependency, and dependencies have to earn their place. Is a small check of the GitHub releases feed, plus a signed DMG download and swap, enough? What does each cost in code, security review, and the delta-update experience?

## Why it matters

Without updates, every bug fix after v0.1 reaches only people who think to check.

## Timebox

Half a day. The answer is a decision with the reasoning.

## Answer

A check of our own; no Sparkle. A release is already a tag, a DMG, and the DMG's SHA-256 (the release
workflow attaches all three), so the whole client is about 150 lines: read GitHub's latest-release
JSON, compare semantic versions (a `-dev` build counts as past its tag), download the DMG to Caches,
check it against the published SHA-256, and open it for the person to drag across. Built in 0034.

What it gives up against Sparkle: delta updates (Zipboy is small, so full DMGs are fine) and
replacing itself in place. In-place replacement is deferred on purpose: a SHA-256 from the same
release page proves the download is intact, not who made it. Authenticity needs the Developer ID
signature from 0058, checked with `SecStaticCodeCheckValidity` against the running app's team, and
only then is swapping the bundle and relaunching safe. Until then the update is offered, never
installed silently, so nothing unsaved is ever at risk.
