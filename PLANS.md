# Pipit Plans

This document contains accepted future direction only.

## Planning Rules

- Only accepted future direction belongs here.
- Plans should be specific enough to guide implementation later.
- When a plan becomes current truth, reflect it into `SPEC.md` or `STATUS.md` and update this file.
- Use `records/decisions/` when a plan requires explicit rationale or a durable policy choice.

## Approved Directions

### Finish Cross-Platform Settings And Key Management

- Outcome: Complete and harden the real Settings surface across Android and iOS, including slot inspection, rename or revoke flows, guest provisioning, owner transfer, local key deletion, and proximity controls backed by shared settings.
- Why this is accepted: The repo already contains the core transport, storage, onboarding, and UI scaffolding; the remaining work is product hardening rather than greenfield design.
- Expected value: Pipit becomes usable as a day-to-day owner and guest management tool rather than only a fob-style companion.
- Preconditions: Preserve the existing BLE management contract, secure-storage model, slot semantics, and Android USB backend boundaries.
- Earliest likely start: In progress already.
- Related ids: `RSH-20260409-001`

### Replace Placeholder Or Temporary Fob Assets With Final Presentation

- Outcome: Swap placeholder or temporary fob assets and viewer assumptions for the final Uguisu presentation without regressing button hit-testing, LED behavior, or cross-platform interaction parity.
- Why this is accepted: The current repo still references placeholder assets and temporary viewer packaging, and the intended product experience depends on a convincing fob surface.
- Expected value: Better product fidelity and fewer asset-pipeline surprises late in delivery.
- Preconditions: Final asset availability, packaging validation on both platforms, and preservation of the existing interaction contract.
- Earliest likely start: After the settings surface is stable or when final assets become available.
- Related ids: `RSH-20260409-001`

## Sequencing

### Near Term

- Initiative: Settings and key-management hardening
  - Why now: It is the largest remaining repo-local product gap that already has substantial implementation in place.
  - Dependencies: BLE management transport, shared crypto and onboarding code, secure storage, Android USB support, and current firmware behavior.
  - Related ids: `RSH-20260409-001`

### Mid Term

- Initiative: Final fob asset and viewer stabilization
  - Why later: It should not displace correctness and hardware validation work on provisioning or settings.
  - Dependencies: Final asset availability and preserved viewer interaction contracts.
  - Related ids: `RSH-20260409-001`

### Deferred But Accepted

- Initiative: Formalize more local workflow helpers on top of the repo operating model
  - Why deferred: The repo now has the core routing model and only needs the orchestrator skill immediately.
  - Revisit trigger: When repeated maintenance patterns justify another reusable in-repo workflow.
  - Related ids: `DEC-20260409-001`
