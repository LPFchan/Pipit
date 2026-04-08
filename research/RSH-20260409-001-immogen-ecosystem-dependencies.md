# RSH-20260409-001 Immogen Ecosystem Dependencies

- Opened: `2026-04-09 05-25-26 KST`
- Recorded by agent: `codex-gpt5-20260409-repo-template-migration`

## Why This Memo Exists

The retired `plan/` brief set mixed Pipit's repo-local work with context about external repos and shared operational dependencies. This memo keeps that reusable context available without treating it as Pipit's own canonical truth.

## External Repos And Ownership Boundaries

### Immogen

- Role: Owns the immobilizer firmware surfaces (`Guillemot` and `Uguisu`) that Pipit interoperates with over BLE and provisioning flows.
- Why Pipit depends on it: Slot semantics, command payloads, provisioning-window behavior, SMP management rules, and replay protection all originate from firmware behavior.
- Repo-local implication: Pipit should treat firmware protocol and security compatibility as a hard constraint, but firmware implementation history does not belong in `SPEC.md` or `STATUS.md` except where it changes Pipit's current reality.

### Whimbrel

- Role: Owns the web dashboard used to generate provisioning QR codes and certain management workflows.
- Why Pipit depends on it: Encrypted owner-transfer QR payloads, guest provisioning shape, and Argon2id parameter compatibility must match what Whimbrel emits.
- Repo-local implication: QR interop assumptions belong in shared onboarding and crypto code, while dashboard implementation details belong here or in future dependency research.

### Bifrost

- Role: Receives a push-triggered sync dispatch from this repo through `.github/workflows/trigger-bifrost-sync.yml`.
- Why Pipit depends on it: It is part of the operator's multi-repo automation story even though it does not change Pipit's product behavior directly.
- Repo-local implication: The workflow exists as an operational integration, not as a product feature or core truth surface.

## Local Vendor And Runtime Dependencies

### Vendored Three.js

- Location: `vendor/three/`
- Current shape: Vendored as a git submodule pinned in-repo for offline or deterministic viewer packaging.
- Why it matters: The iOS viewer path uses a bundled `viewer.html` plus `LocalSchemeHandler` and local module resolution instead of a CDN dependency.
- Repo-local implication: Viewer fixes or version changes should be treated as Pipit implementation work, but general vendor rationale belongs in research and worklogs rather than in `SPEC.md`.

### Shared KMP Contracts

- Location: `shared/src/commonMain/kotlin/com/immogen/pipit/`
- Current shape: Shared BLE transport interfaces, onboarding gate, QR parser, and proximity settings keys are the interop seam between platform UI code and external protocol expectations.
- Repo-local implication: Pipit's product truth should reference these as implementation anchors, while cross-repo compatibility details stay here unless they become durable project-level invariants.

## Operational Notes

- This repo currently has active local edits across Android, iOS, viewer, and project files, so dependency-sensitive validation should use targeted staging and explicit worklogs.
- Future dependency changes should create a new `RSH-*` when they add reusable context instead of growing `STATUS.md` into a dependency diary.
- If Pipit ever adopts recurring, scheduled upstream review as a managed practice, that would justify adding `upstream-intake/` later. It is intentionally omitted today.
