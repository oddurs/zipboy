---
id: 48
uid: df9eea83-9129-482c-aed9-2f36aec68337
title: A `zipboy` command-line tool
type: feature
status: backlog
milestone: later
created: 2026-10-20
updated: 2026-10-20
priority: p3
effort: m
area: system
---

## Problem

Scripts and terminals can't use Zipboy's safety rules or its metadata handling.

## Proposal

A small CLI on ZipboyKit: list, extract with the same safety rules, and create.

## Acceptance criteria

- [ ] `zipboy list|extract|create` with `--help` and man page, sharing ZipboyKit
