# Design: SnapCert Admin Guide

**Date:** 2026-03-21
**Status:** Approved
**Deliverable:** `docs/admin-guide.md`

## Problem

SnapCert is ready for deployment but other admins have no reference document. Without documentation, the tool cannot be handed off, reviewed by peers, or supported by anyone other than its author.

## Scope

A single admin-facing markdown document covering everything needed to understand, deploy, configure, and support SnapCert. No scripting. No implementation changes.

## Out of Scope

- SCCM install/uninstall scripts (deferred until ready to deploy)
- MSI packaging (future, post-stabilisation)
- End-user documentation (SnapCert has no end users)

## Document Structure

| Section | Purpose |
|---------|---------|
| What SnapCert Does | Plain English summary, one paragraph |
| Requirements | OS, PowerShell, AD CS topology, domain membership, run-as |
| How It Works | End-to-end renewal flow |
| Certificate Request Details | Template, key length, Subject, SANs |
| Configuration Reference | Every snapcert.json key, default, description |
| CLI Usage | All switches with examples |
| Logging and Monitoring | Log file, Event Log, SIEM guidance |
| SCCM Deployment Notes | Install path, detection method, scheduled task |
| Known Limitations | Single template, new enrollment vs renewal, deferred items |

## Decisions

- **Format:** Markdown — renders on GitHub, easy to maintain alongside code
- **Location:** `docs/admin-guide.md` — top-level docs, discoverable
- **Audience:** Windows Server admins familiar with SCCM and AD CS, not necessarily familiar with PowerShell scripting
- **Tone:** Direct and factual — no marketing language, no filler
