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
