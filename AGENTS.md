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

If the repo includes reusable workflows, then also read `skills/README.md` and the relevant `skills/<name>/SKILL.md`.

When writing into an artifact directory, read that directory's `README.md` first. If it defines a default shape or canonical example, follow it.

## Operating Rules

- Keep durable truth in repo files, not only in chat.
- Route work using the routing ladder in `REPO.md`.
- Preserve the boundary between `SPEC.md`, `STATUS.md`, `PLANS.md`, `INBOX.md`, `research/`, `records/decisions/`, and `records/agent-worklogs/`.
- Treat `.github/copilot-instructions.md` as the canonical source for Pipit-specific build, test, architecture, BLE, and security constraints.
- Prefer appending to the current relevant `LOG-*` instead of creating a new one unless the work is materially distinct or reuse would hurt clarity.
- Prefer the local `README.md` shape over ad hoc formatting when it defines one.
- When hooks or CI enforcement are enabled, commit messages must satisfy the provenance rules in `REPO.md` and pass `scripts/check-commit-standards.sh`.
- Bootstrap or migration exceptions must be explicit in the commit message. Do not treat missing trailers as an acceptable shortcut.

## Enforcement

When you write or update repo artifacts, adherence to the repo's ruleset is required.

- Do not invent a new document shape when the repo already provides a canonical surface, directory `README.md`, or explicit template.
- Do not collapse truth, plans, decisions, research, inbox intake, and worklogs into one mixed artifact.
- Do not replace normalized repo artifacts with freeform chat summaries.
- If a repo-specific instruction conflicts with a generic formatting habit, keep the Pipit repo artifact compliant and surface the mismatch explicitly.

## Skills

`skills/<name>/SKILL.md` files are reusable procedures for bounded workflows.

- Keep them procedural.
- Do not duplicate canonical repo policy inside them.
- Use them to standardize repeatable tasks, escalation triggers, and output shape.
