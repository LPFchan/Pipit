# LOG-20260409-004: Rename Canonical Rules Doc To REPO

Opened: 2026-04-09 07-42-14 KST
Recorded by agent: codex-gpt5-20260409-repo-rename

## Metadata

- Run type: orchestrator
- Goal: migrate the canonical repo rules doc from `repo-operating-model.md` to `REPO.md` without losing Pipit-specific truth or workflow constraints
- Related ids: DEC-20260409-001, DEC-20260409-002

## Task

Rename the root repo contract to `REPO.md`, update thin entrypoints and active guidance to point at the new canonical name, and preserve historical artifact truth where older records still mention the predecessor filename.

## Scope

- In scope: repo-root contract naming, agent entrypoints, active README guidance, the local repo skill, and examples that teach the canonical doc surface
- Out of scope: rewriting older decision records or worklogs whose `repo-operating-model.md` references are part of append-only historical context

## Entry 2026-04-09 07-42-14 KST

- Action: audited the current repo contract surfaces and all repo-local references to `repo-operating-model.md`
- Files touched: none
- Checks run: `rg -uu -n "repo-operating-model\\.md|REPO\\.md" .`
- Output: confirmed `repo-operating-model.md` existed at repo root, `REPO.md` did not, and the remaining live references were concentrated in active docs, the local skill, and a worklog README example
- Blockers: none
- Next: rename the canonical rules doc and update the active entrypoints

## Entry 2026-04-09 07-48-00 KST

- Action: renamed `repo-operating-model.md` to `REPO.md`, updated active repo guidance to point at `REPO.md`, and added this worklog to record the migration
- Files touched: `REPO.md`, `AGENTS.md`, `README.md`, `skills/README.md`, `skills/repo-orchestrator/SKILL.md`, `records/agent-worklogs/README.md`, `records/agent-worklogs/LOG-20260409-004-rename-canonical-rules-doc-to-repo.md`
- Checks run: `rg -uu -n "repo-operating-model\\.md|REPO\\.md" .`
- Output: the canonical contract now lives at `REPO.md`; current entrypoints and examples point to the new name; older worklogs and decisions retain the predecessor filename where it reflects historical state
- Blockers: none
- Next: verify there are no stale active references to `repo-operating-model.md`

## Entry 2026-04-09 08-05-00 KST

- Action: updated the repo contract, worklog guide, agent entrypoint, and orchestration guidance to prefer appending to the current relevant `LOG-*` instead of creating a new worklog for each meaningful commit
- Files touched: `REPO.md`, `AGENTS.md`, `README.md`, `.github/copilot-instructions.md`, `skills/repo-orchestrator/SKILL.md`, `records/agent-worklogs/README.md`, `records/agent-worklogs/LOG-20260409-004-rename-canonical-rules-doc-to-repo.md`
- Checks run: template-to-local wording comparison, repo-wide wording audit for worklog and provenance guidance
- Output: Pipit now preserves strict artifact-linked commit provenance while explicitly allowing normal commits to reference updated existing artifacts; worklogs are append-first unless a distinct execution record improves clarity
- Blockers: none
- Next: verify there are no remaining active docs that imply a new `LOG-*` is the default for each meaningful commit
