# Pipit Status

This document tracks current accepted operational truth for the repo.

## Snapshot

- Last updated: 2026-04-09
- Overall posture: `active`
- Current focus: Keep the mobile app moving while using the canonical root docs and records surfaces instead of the retired brief workflow.
- Highest-priority blocker: Cross-platform settings and key-management behavior still need real-hardware validation against the existing BLE and firmware contracts.
- Next operator decision needed: Whether to prioritize settings hardening and hardware validation before the final 3D asset swap.
- Related decisions: `DEC-20260409-001`

## Current State Summary

Pipit is an active Kotlin Multiplatform mobile repo with Android, iOS, and shared crypto or transport code in place. The shared module contains AES-CCM payload building, Argon2id-backed provisioning helpers, onboarding gates, QR parsing, and shared proximity settings. Android includes the BLE proximity service, settings UI, onboarding UI, and USB backend. iOS includes a SwiftUI shell, BLE service, onboarding and settings flows, and a bundled WebKit-backed Three.js viewer path for the fob surface. The repo now uses canonical truth, status, planning, research, decision, and worklog surfaces, and the previous brief-based planning system has been retired.

## Active Phases Or Tracks

### Cross-Platform Companion App

- Goal: Deliver a stable phone-key experience across Android and iOS.
- Status: `in progress`
- Why this matters now: The core app surfaces exist, but the repo still depends on field validation and continued convergence between the shared crypto model, mobile UIs, and external firmware behavior.
- Current work: Maintaining onboarding, home, settings, and management flows while in-flight platform work continues in the working tree.
- Exit criteria: Both platforms complete core onboarding, manual lock or unlock, proximity behavior, and settings operations against real hardware without protocol regressions.
- Dependencies: Immogen firmware behavior, Whimbrel QR payload compatibility, platform BLE availability, and secure local key storage.
- Risks: Cross-platform behavior drift, stale docs describing old UI architecture, and dependence on live hardware for full validation.
- Related ids: `RSH-20260409-001`

### Settings And Key Management Hardening

- Goal: Make slot inspection, provisioning, rename, revoke, migration, recovery, and proximity controls reliable enough to treat Settings as a first-class product surface.
- Status: `in progress`
- Why this matters now: The repo contains substantial Settings and onboarding code, but the remaining risk is not scaffolding; it is correctness, edge-case handling, and hardware-backed validation.
- Current work: Loading slot state through the BLE management transport, wiring destructive actions through shared key storage and platform services, and keeping the Android USB path isolated behind its backend contract.
- Exit criteria: Settings flows are exercised against hardware, match slot and PIN rules, and behave consistently across both mobile platforms.
- Dependencies: `shared/src/commonMain/kotlin/com/immogen/pipit/ble`, `shared/src/commonMain/kotlin/com/immogen/pipit/onboarding`, Android USB support, and current firmware command semantics.
- Risks: Firmware or dashboard protocol drift, destructive-key actions without enough end-to-end testing, and UI behavior moving ahead of verified device workflows.
- Related ids: `RSH-20260409-001`

### Repo Operating Model Adoption

- Goal: Keep project truth, plans, research, decisions, and execution history legible in-repo.
- Status: `done`
- Why this matters now: The repo had durable information mixed into agent-specific briefs, which made current truth and accepted future direction hard to separate.
- Current work: Using `SPEC.md`, `STATUS.md`, `PLANS.md`, `research/`, and `records/` as the canonical routing surfaces going forward.
- Exit criteria: Future work lands in the new canonical surfaces instead of recreating a parallel planning layer.
- Dependencies: Contributor adherence, local skill guidance, and commit provenance discipline.
- Risks: Habit drift back toward ad hoc brief files or chat-only status tracking.
- Related ids: `DEC-20260409-001`, `LOG-20260409-001`

## Recent Changes To Project Reality

- Date: 2026-04-09
  - Change: Adopted the repo-template operating model, added canonical truth and record surfaces, and retired the older brief directory.
  - Why it matters: Current truth, accepted plans, research, decisions, and execution history are now separated explicitly instead of being mixed together.
  - Related ids: `DEC-20260409-001`, `LOG-20260409-001`
- Date: 2026-04-09
  - Change: Confirmed the repo currently contains in-flight local edits across Android, iOS, viewer, and project files outside this docs migration.
  - Why it matters: Any product validation or release decision must account for worktree state that is ahead of the last clean commit on `main`.
  - Related ids: `LOG-20260409-001`

## Active Blockers And Risks

- Blocker or risk: Real-hardware validation is still required for secure management and proximity behavior.
  - Effect: Repo status can outpace what has been proven against actual vehicle and firmware behavior.
  - Owner: Operator plus active implementation agents.
  - Mitigation: Validate onboarding, settings, and destructive slot actions against current Immogen firmware before treating the flows as production-stable.
  - Related ids: `RSH-20260409-001`
- Blocker or risk: Pipit depends on external repos and protocols that live outside this codebase.
  - Effect: Changes in `Immogen`, `Whimbrel`, or operational tooling can silently invalidate assumptions in Pipit.
  - Owner: Operator.
  - Mitigation: Keep durable dependency notes in research and re-check interop whenever the external protocol or QR flow changes.
  - Related ids: `RSH-20260409-001`
- Blocker or risk: The working tree is currently dirty with app-level changes unrelated to this migration.
  - Effect: Repo truth may diverge temporarily from the last clean committed state, and future commits need careful staging discipline.
  - Owner: Current implementers.
  - Mitigation: Use targeted staging, keep worklogs explicit, and validate only the surfaces that actually changed in a given commit.
  - Related ids: `LOG-20260409-001`

## Immediate Next Steps

- Next: Validate Android and iOS settings, onboarding, and management flows against current hardware and firmware behavior.
  - Owner: Operator plus active implementation agents.
  - Trigger: Before treating current settings and destructive key actions as stable.
  - Related ids: `RSH-20260409-001`
- Next: Keep `SPEC.md`, `STATUS.md`, `PLANS.md`, and the records surfaces current as feature work continues.
  - Owner: Orchestrator and future workers.
  - Trigger: Any accepted truth or plan change, notable decision, or execution session.
  - Related ids: `DEC-20260409-001`, `LOG-20260409-001`
