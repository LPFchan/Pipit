# RSH-20260409-001: Immogen Ecosystem Dependencies

Opened: 2026-04-09 05-25-26 KST
Recorded by agent: codex-gpt5-20260409-repo-template-migration

## Metadata

- Status: completed
- Question: Which external repos and shared dependencies materially constrain Pipit's local truth and workflow?
- Trigger: repo-template migration
- Related ids: DEC-20260409-001, LOG-20260409-001

## Research Question

Which external repos, vendor dependencies, and operational integrations are important enough to preserve as reusable Pipit context without promoting them into Pipit's own truth docs?

## Why This Belongs To This Repo

The retired brief workflow mixed Pipit's repo-local work with context about external repos and shared operational dependencies. This memo preserves that reusable ecosystem context without treating it as Pipit's canonical truth.

## Findings

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

### Vendored Three.js

- Location: `vendor/three/`
- Current shape: Vendored as a git submodule pinned in-repo for offline or deterministic viewer packaging.
- Why it matters: The iOS viewer path uses a bundled `viewer.html` plus `LocalSchemeHandler` and local module resolution instead of a CDN dependency.
- Repo-local implication: Viewer fixes or version changes should be treated as Pipit implementation work, but general vendor rationale belongs in research and worklogs rather than in `SPEC.md`.

### Shared KMP Contracts

- Location: `shared/src/commonMain/kotlin/com/immogen/pipit/`
- Current shape: Shared BLE transport interfaces, onboarding gate, QR parser, and proximity settings keys are the interop seam between platform UI code and external protocol expectations.
- Repo-local implication: Pipit's product truth should reference these as implementation anchors, while cross-repo compatibility details stay here unless they become durable project-level invariants.

## Promising Directions

- Keep future firmware, dashboard, or vendor dependency changes in new `RSH-*` memos instead of growing `STATUS.md` into a dependency diary.
- Re-check interop whenever `Immogen` changes slot semantics, management commands, or provisioning-window behavior.
- Re-check QR compatibility whenever `Whimbrel` changes encrypted owner-transfer payloads or Argon2id parameters.

## Dead Ends Or Rejected Paths

- Promoting external implementation history into `SPEC.md` or `STATUS.md` was rejected because it would collapse Pipit's local truth with cross-repo background context.
- Introducing `upstream-intake/` now was rejected because Pipit is not currently run as a recurring downstream fork-review repo.

## Recommended Routing

- Keep cross-repo dependency context in `research/`.
- Reflect only Pipit-local accepted reality into `STATUS.md`.
- Record future workflow or policy changes in `records/decisions/`.
- Record implementation sessions that touch dependency-sensitive code in `records/agent-worklogs/`.
