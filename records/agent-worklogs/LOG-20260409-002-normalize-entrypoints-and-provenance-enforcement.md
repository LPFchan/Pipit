# LOG-20260409-002: Normalize Entrypoints And Provenance Enforcement

Opened: 2026-04-09 06-55-23 KST
Recorded by agent: codex-gpt5-20260409-provenance-enforcement

## Metadata

- Run type: orchestrator
- Goal: normalize repo-template entrypoints and activate commit provenance enforcement without losing Pipit-specific workflow rules
- Related ids: DEC-20260409-002, DEC-20260409-001

## Task

Introduce root `AGENTS.md` and `CLAUDE.md`, normalize the touched artifact guides and bootstrap records toward repo-template shape, and add local plus CI commit provenance enforcement.

## Scope

- In scope: repo-root instruction entrypoints, repo operating model wording, touched directory guides, touched bootstrap artifacts, local hook files, validator scripts, CI workflow, and hook installation
- In scope: preserving Pipit-specific build, test, BLE, and security guidance by pointing back to `.github/copilot-instructions.md`
- Out of scope: unrelated Android, iOS, shared, or vendor implementation changes

## Entry 2026-04-09 06-55-23 KST

- Action: audited the repo-template scaffold and commit-enforcement files, mapped them onto Pipit's existing repo-template adoption, then drafted thin `AGENTS.md` and `CLAUDE.md`, normalized the touched guides and bootstrap artifacts, and added the local hook and CI files
- Files touched: `AGENTS.md`, `CLAUDE.md`, `repo-operating-model.md`, `README.md`, `STATUS.md`, `research/README.md`, `research/RSH-20260409-001-immogen-ecosystem-dependencies.md`, `records/decisions/README.md`, `records/decisions/DEC-20260409-001-adopt-repo-template-operating-model.md`, `records/decisions/DEC-20260409-002-enable-commit-provenance-enforcement.md`, `records/agent-worklogs/README.md`, `records/agent-worklogs/LOG-20260409-001-repo-template-migration.md`, `records/agent-worklogs/LOG-20260409-002-normalize-entrypoints-and-provenance-enforcement.md`, `.githooks/commit-msg`, `scripts/`, `.github/workflows/commit-standards.yml`
- Checks run: template-to-local doc comparison, hook or CI file inspection, local hook installation, commit-message validation
- Output: Pipit now has repo-root instruction entrypoints, normalized touched artifact-writing guides, a new decision and worklog for provenance enforcement, and reusable hook or CI enforcement copied from repo-template
- Blockers: none
- Next: keep future touched artifacts in template shape and rely on the installed hook plus CI to enforce provenance on new commits

## Entry 2026-04-09 07-15-22 KST

- Action: converted `CLAUDE.md` from a thicker local instruction file into the scaffold-style compatibility shim that points directly at `AGENTS.md`
- Files touched: `CLAUDE.md`, `records/agent-worklogs/LOG-20260409-002-normalize-entrypoints-and-provenance-enforcement.md`
- Checks run: scaffold-to-local file comparison
- Output: `CLAUDE.md` no longer duplicates repo policy and now matches the repo-template expectation that Claude-specific entrypoints remain a shim
- Blockers: none
- Next: commit and push the shim change
