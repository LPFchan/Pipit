# DEC-20260409-001: Adopt Repo-Template Operating Model

Opened: 2026-04-09 05-25-27 KST
Recorded by agent: codex-gpt5-20260409-repo-template-migration

## Metadata

- Status: accepted
- Deciders: operator, orchestrator
- Related ids: RSH-20260409-001, LOG-20260409-001

## Decision

Pipit adopts the repo-template operating model as its canonical repo-governance structure.

## Context

The repo previously stored durable truth, historical execution, open plans, and cross-repo context inside a retired brief directory of agent-specific documents. That format worked as a short-lived coordination mechanism, but it blurred the boundaries between current project truth, accepted future direction, external dependency context, historical execution logs, and durable workflow decisions.

As the repo accumulated Android, iOS, shared KMP, viewer, and cross-repo ecosystem work, the lack of canonical surfaces made it harder to answer simple questions about what Pipit is, what is true right now, and what remains accepted but unfinished.

## Options Considered

### Keep The Retired Brief Workflow Active

- Upside: no migration effort
- Downside: keeps truth, plans, research, and execution history mixed together

### Adopt Repo-Template As The Canonical Repo Structure

- Upside: gives Pipit explicit root surfaces for truth, status, plans, research, decisions, and worklogs
- Upside: matches the repo-template operating model already chosen for this workspace
- Downside: requires a one-time migration and contributor retraining

### Overlay Repo-Template Without Retiring The Old Surface

- Upside: lower short-term disruption
- Downside: leaves two competing systems and weakens the point of normalization

## Rationale

Full repo-template adoption gives Pipit one legible in-repo operating system instead of a split between ad hoc brief files and canonical repo artifacts. The extra migration overhead is worth the clearer routing, provenance, and recovery story.

## Consequences

- `SPEC.md`, `STATUS.md`, `PLANS.md`, and `INBOX.md` are the canonical root surfaces.
- `research/` holds curated dependency and exploration notes.
- `records/decisions/` holds durable decisions.
- `records/agent-worklogs/` holds execution history.
- `repo-operating-model.md` defines the routing and provenance rules.
- The local `skills/repo-orchestrator/` helper is kept as the only repo-template skill for now.
- Stable IDs use `IBX-*`, `RSH-*`, `DEC-*`, and `LOG-*`.
- Commit provenance uses `project: pipit`, `agent: <agent-id>`, `role: ...`, and `artifacts: ...`.
- `upstream-intake/` remains omitted because Pipit is not currently run as a recurring downstream fork-review repo.
- Cross-repo implementation history for `Immogen` and `Whimbrel` is summarized as dependency research instead of being promoted into Pipit's project truth.
