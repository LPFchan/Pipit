# LOG-20260409-001: Repo-Template Migration

Opened: 2026-04-09 05-25-28 KST
Recorded by agent: codex-gpt5-20260409-repo-template-migration

## Metadata

- Run type: orchestrator
- Goal: migrate Pipit from the retired brief workflow to canonical repo-template surfaces
- Related ids: DEC-20260409-001, RSH-20260409-001

## Task

Migrate Pipit to the repo-template operating model without changing Android, iOS, KMP, or vendor implementation files as part of the staged migration set.

## Scope

- In scope: root truth docs, research or decisions or worklogs scaffolding, active guidance docs, and retirement of the old brief directory
- In scope: provenance-bearing migration commit preparation
- Out of scope: Android, iOS, shared KMP, or vendor code changes

## Entry 2026-04-09 05-25-28 KST

- Action: reviewed the retired brief documents, current repo docs, and repo state, then created `repo-operating-model.md`, `SPEC.md`, `STATUS.md`, `PLANS.md`, `INBOX.md`, `research/`, `records/decisions/`, and `records/agent-worklogs/`
- Files touched: root canonical docs, bootstrap artifact directories, `README.md`, `.github/copilot-instructions.md`, `iosApp/README.md`, `PIPIT_MASTER_ARCHITECTURE.md`
- Checks run: repo inspection, diff review, provenance-aware commit preparation
- Output: routed cross-repo context into `RSH-20260409-001`, recorded the operating-model decision in `DEC-20260409-001`, retired the old brief directory, and committed the migration with provenance trailers
- Blockers: none
- Next: use the new canonical docs for future routing and keep future dependency drift in new `RSH-*` artifacts

## Entry 2026-04-09 08-25-00 KST

- Action: compared current `SPEC.md` and `RSH-20260409-001` against the repo-template guidance, their first repo-template versions, the pre-migration README and Copilot guidance, the architecture heading map, and the retired plan brief inventory
- Files touched: `SPEC.md`, `research/README.md`, `research/RSH-20260409-001-immogen-ecosystem-dependencies.md`, `records/agent-worklogs/LOG-20260409-001-repo-template-migration.md`
- Checks run: `git log --follow -- SPEC.md`, `git log --follow -- research/RSH-20260409-001-immogen-ecosystem-dependencies.md`, historical `git show` reads for `488f655`, `f03ae6b`, and `488f655^`
- Output: restored a project-native spec shape around phone-key lifecycle, slots, user-facing capabilities, native boundaries, and protocol invariants; restored the research memo's ownership-boundary structure while preserving normalized opening, related IDs, and routing recommendations
- Blockers: none
- Next: verify the reconciled docs keep repo-template boundaries while reading like Pipit artifacts

## Entry 2026-04-09 08-32-00 KST

- Action: corrected `research/README.md` to match the current repo-template scaffold text instead of carrying local wording drift in the directory-level writing guide
- Files touched: `research/README.md`, `records/agent-worklogs/LOG-20260409-001-repo-template-migration.md`
- Checks run: compared local `research/README.md` against `/Users/yeowool/Documents/repo-template/scaffold/research/README.md`
- Output: the generic research writing guide now remains template-aligned; Pipit-specific ownership-boundary organization stays only in `RSH-20260409-001`
- Blockers: none
- Next: verify the guide has no unintended diff from the scaffold
