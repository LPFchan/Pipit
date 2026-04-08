# DEC-20260409-001 Adopt Repo-Template Operating Model

- Opened: `2026-04-09 05-25-27 KST`
- Recorded by agent: `codex-gpt5-20260409-repo-template-migration`

## Decision

Pipit adopts the repo-template operating model as its canonical repo-governance structure.

## Context

The repo previously stored durable truth, historical execution, open plans, and cross-repo context inside a `plan/` directory of agent-specific briefs. That format worked as a short-lived coordination mechanism, but it blurred the boundaries between:

- current project truth
- accepted future direction
- external dependency context
- historical execution logs
- durable workflow decisions

As the repo accumulated Android, iOS, shared KMP, viewer, and cross-repo ecosystem work, the lack of canonical surfaces made it harder to answer simple questions about what Pipit is, what is true right now, and what remains accepted but unfinished.

## Adopted Changes

- `SPEC.md`, `STATUS.md`, `PLANS.md`, and `INBOX.md` are now the canonical root surfaces.
- `research/` holds curated dependency and exploration notes.
- `records/decisions/` holds durable decisions.
- `records/agent-worklogs/` holds execution history.
- `repo-operating-model.md` defines the routing and provenance rules.
- The local `skills/repo-orchestrator/` helper is kept as the only repo-template skill for now.
- Stable IDs use `IBX-*`, `RSH-*`, `DEC-*`, and `LOG-*`.
- Commit provenance uses `project: pipit`, `agent: <agent-id>`, `role: ...`, and `artifacts: ...`.

## Explicit Non-Adoptions

- `upstream-intake/` is omitted because Pipit is not currently being run as a recurring downstream fork-review repo.
- The old `plan/` brief directory is retired instead of being preserved as an active parallel surface.
- Cross-repo implementation history for `Immogen` and `Whimbrel` is not promoted into Pipit's project truth. It is summarized as dependency research instead.

## Consequences

- Future contributors should update `SPEC.md`, `STATUS.md`, `PLANS.md`, `research/`, and `records/` instead of creating new agent-brief files.
- `PIPIT_MASTER_ARCHITECTURE.md` remains the deep protocol and security reference, but project-level truth now lives in the canonical root surfaces.
- A small amount of migration overhead is accepted in exchange for much clearer repo-local memory and provenance going forward.
