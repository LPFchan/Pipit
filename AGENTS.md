# Agent Instructions

This repo uses repo-template.

Treat `AGENTS.md` as a compatibility entrypoint for tools that look for repo-root agent instructions. The canonical repo contract lives in `REPO.md`.

## Read First

- `REPO.md`
- `SPEC.md`
- `STATUS.md`
- `PLANS.md`
- `INBOX.md`
- `.github/copilot-instructions.md`

Always read `skills/README.md` and the relevant `skills/<name>/SKILL.md` for the workflow you are executing.
Treat skills as readable repo procedures even if the current agent runtime does not auto-load `SKILL.md` files.

When writing into an artifact directory, read that directory's `README.md` first. If it defines a default shape or canonical example, follow it.

## Operating Rules

- Keep durable truth in repo files, not only in external tools.
- Route work using the routing ladder in `REPO.md`.
- Preserve the boundary between `SPEC.md`, `STATUS.md`, `PLANS.md`, `INBOX.md`, `research/`, `records/decisions/`, and `records/agent-worklogs/`.
- Treat `.github/copilot-instructions.md` as the canonical source for Pipit-specific build, test, architecture, BLE, and security constraints.
- Treat `INBOX.md` as pressure, not a backlog. During inbox review, cluster capture and promote only survived triage.
- Promote sparsely. Do not mirror one evolving thought into research, decisions, plans, spec, status, upstream records, and worklogs.
- Prefer appending to the current relevant `LOG-*` instead of creating a new one unless the work is materially distinct or reuse would hurt clarity.
- Prefer the local `README.md` shape over ad hoc formatting when it defines one.
- When hooks or CI enforcement are enabled, commit messages must satisfy the provenance rules in `REPO.md` and pass `scripts/check-commit-standards.sh`.
- Bootstrap or migration exceptions must be explicit in the commit message. Do not treat missing trailers as an acceptable shortcut.

## Enforcement

When you write or update repo artifacts, adherence to the repo's ruleset is required.

- Do not invent a new document shape when the repo already provides a canonical surface, directory `README.md`, or explicit template.
- Do not collapse truth, plans, decisions, research, inbox capture, and worklogs into one mixed artifact.
- Do not promote exploratory debate into `SPEC.md`, `STATUS.md`, `PLANS.md`, or `records/decisions/` until there is a concise accepted outcome for that layer.
- Do not turn an inbox review into a giant digest of every low-confidence idea. Report counts or clusters when full detail does not protect focus.
- Do not replace normalized repo artifacts with freeform external-tool summaries.
- If a repo-specific instruction conflicts with a generic formatting habit, keep the Pipit repo artifact compliant and surface the mismatch explicitly.

## Skills

`skills/<name>/SKILL.md` files are reusable procedures for bounded workflows.

- `skills/repo-orchestrator/SKILL.md` and `skills/daily-inbox-pressure-review/SKILL.md` are required baseline repo-template procedures in this repo.
- `skills/upstream-intake/SKILL.md` is intentionally omitted unless `upstream-intake/` is enabled later.
- Keep them procedural.
- Do not duplicate canonical repo policy inside them.
- Use them to standardize repeatable tasks, escalation triggers, and output shape.
