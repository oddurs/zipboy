---
id: 100
uid: 6401df7a-e185-4343-9576-49f34197f9b7
title: Unpack whatever lands in a watched folder
type: feature
status: backlog
milestone: later
created: 2026-11-06
updated: 2026-11-06
priority: p3
effort: m
area: system
---

## Problem

People who download many archives unpack each one by hand.

## Proposal

A chosen folder, watched with `FileWatcher`, whose new archives are extracted beside themselves. It means
running in the background, which sits badly with an app built on having few visible choices, so it
waits until people ask. Folder Actions and Shortcuts can already do this through the `extract` script
command, which may be the better answer.

## Acceptance criteria

- [ ] An archive that finishes arriving in the folder is extracted once, not while it's still being written
- [ ] A password-protected archive is left alone with a notice, never a prompt from nowhere
