---
id: 79
uid: 60823e0f-7c08-4ecb-a6a1-4a37c68c5b90
title: Long work shows on the Dock and says when it's finished
type: feature
status: done
milestone: v0.3
depends_on:
- 29
created: 2026-11-02
updated: 2026-11-02
priority: p2
effort: s
area: shell
---

## Problem

Once someone switches away during a long add, extract, or save, nothing tells them how it is going
or when it has finished. Mail, Finder, and Safari downloads all show this on the Dock icon.

## Proposal

Drive the Dock tile from the operation's `Progress` (0029): a bar drawn into `NSApp.dockTile`
while any operation longer than a second runs, cleared when the last one ends. When an operation
finishes while Zipboy isn't frontmost, post a `UNUserNotificationCenter` notification ("Extracted
“Photos.zip”") whose click brings the window forward, and bounce the Dock once
(`requestUserAttention(.informationalRequest)`) if notifications are off.

## Acceptance criteria

- [x] The Dock icon shows a progress bar during an operation over a second and none afterwards, checked by a test on the tile's content view
- [x] Two overlapping operations show their combined fraction
- [x] Finishing while another app is frontmost posts one notification naming the archive; finishing while frontmost posts none
- [x] Clicking the notification brings that archive's window to the front

## 2026-11-02

Evidence. TaskWatcherTests: one notice naming the archive when a task of a second or more ends out of sight; none when frontmost, quick, or stopped (the stopped case fails with the cancel check removed); the Dock tile shows the combined fraction of two tasks and clears when both end; a notice's archive name brings that window forward. Criterion 3 is checked through a recording Notifier: the real UNUserNotificationCenter path (authorisation, then a notice, or a Dock bounce if refused) only runs inside an app bundle and was not seen on screen this session.
