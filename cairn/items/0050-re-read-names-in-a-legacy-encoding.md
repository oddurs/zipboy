---
id: 50
uid: e666ec8b-8617-4136-a5ea-9af10b471a3a
title: Re-read names in a legacy encoding
type: feature
status: backlog
milestone: later
created: 2026-10-20
updated: 2026-10-20
priority: p3
effort: s
area: archive
---

## Problem

ZIPs made on old Japanese or Russian Windows show garbled names, because they are neither UTF-8 nor CP437.

## Proposal

A View > Text Encoding menu that re-decodes names, as Archive Utility can't.

## Acceptance criteria

- [ ] Choosing Shift-JIS on a Shift-JIS fixture shows the right names
