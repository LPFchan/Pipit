# Pipit Repo Operating Model

This document defines how Pipit's repo-local truth, status, plans, research, decisions, and execution history are kept separate and durable over time.

## Purpose

Pipit is run as a multi-agent, multi-surface project with cross-repo dependencies on Immogen firmware and the Whimbrel dashboard. This operating model keeps the repo legible by separating:

- what Pipit is supposed to be
- what is true right now
- what future work is accepted
- what was learned
- what was decided
- what happened during execution

## Canonical Surfaces

| Surface | Role | Mutability |
| --- | --- | --- |
| `SPEC.md` | Durable project-level truth for Pipit. | rewritten |
| `STATUS.md` | Current accepted operational reality. | rewritten |
| `PLANS.md` | Accepted future direction that is not current truth yet. | rewritten |
| `INBOX.md` | Untriaged intake waiting for routing. | append then purge |
| `research/` | Curated reusable research and dependency notes. | append by new file |
| `records/decisions/` | Durable decision records with rationale. | append by new file |
| `records/agent-worklogs/` | Execution history for migrations, runs, and implementation sessions. | append by new file |
| `PIPIT_MASTER_ARCHITECTURE.md` | Deep protocol, security, provisioning, and system-design reference. | rewritten deliberately |

`upstream-intake/` is intentionally omitted for now. Pipit depends on upstream projects, but this repo is not being run as a recurring downstream fork-review system.

## Separation Rules

- `SPEC.md` is not a changelog.
- `STATUS.md` is not a transcript.
- `PLANS.md` is not a brainstorm dump.
- `INBOX.md` is not durable truth.
- `research/` is not raw execution history.
- `records/decisions/` is not the same thing as `records/agent-worklogs/`.
- Cross-repo context about `Immogen`, `Whimbrel`, `Bifrost`, or vendored dependencies belongs in research or dependency notes unless it changes Pipit's own truth directly.

## Routing Ladder

When new work arrives, route it in this order:

1. Untriaged intake -> `INBOX.md`
2. Durable project truth -> `SPEC.md`
3. Current operational reality -> `STATUS.md`
4. Accepted future direction -> `PLANS.md`
5. Reusable research or dependency analysis -> `research/`
6. Durable decision with rationale -> `records/decisions/`
7. Execution history -> `records/agent-worklogs/`

One task may legitimately touch more than one surface. Example: a feature kickoff can create a `DEC-*`, update `PLANS.md`, and later append a `LOG-*`.

## Roles

### Operator

The operator is the final authority on product direction, acceptance of truth changes, and escalation outcomes.

### Orchestrator

The orchestrator owns routing and synthesis. It may update `SPEC.md`, `STATUS.md`, `PLANS.md`, create research memos, write decisions, and create worklogs.

### Worker

Workers execute bounded tasks. They should prefer creating `LOG-*` artifacts and proposing truth changes through the orchestrator instead of rewriting canonical docs ad hoc.

## Write Rules

- Update `SPEC.md`, `STATUS.md`, and `PLANS.md` only when the accepted state actually changes.
- Keep `INBOX.md` short-lived and purge entries once they are reflected elsewhere.
- Put reusable dependency or ecosystem context in `research/`.
- Record durable product, architecture, or workflow choices in `records/decisions/`.
- Record migrations, implementations, and noteworthy execution sessions in `records/agent-worklogs/`.
- When `PIPIT_MASTER_ARCHITECTURE.md` conflicts with `SPEC.md`, `STATUS.md`, or current code on non-protocol implementation details, treat the architecture document as authoritative for protocol and security only, and prefer the newer project-level docs for repo reality.

## Stable IDs

Use these prefixes:

- `IBX-YYYYMMDD-NNN`
- `RSH-YYYYMMDD-NNN`
- `DEC-YYYYMMDD-NNN`
- `LOG-YYYYMMDD-NNN`

Numbering is per day and per artifact type using the least available `NNN`.

Every stable-ID-bearing artifact should include:

- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

## Commit Provenance

After adopting this model, commits should include these trailers:

- `project: pipit`
- `agent: <agent-id>`
- `role: orchestrator|worker|subagent|operator`
- `artifacts: <artifact-id>[, <artifact-id>...]`

Normal commits should reference at least one stable artifact. Artifact-less commits are migration/bootstrap exceptions only.

## Skills

This repo keeps a local `skills/repo-orchestrator/` workflow as a lightweight helper for routing future work into the correct artifact layer. It complements this document and does not replace it.
