# Pipit Repo Contract

This document is the canonical repo contract for Pipit.

## Purpose

Pipit is run as a multi-agent, multi-surface project with cross-repo dependencies on Immogen firmware and the Whimbrel dashboard. The goal is simple:

- keep canonical truth in-repo
- keep noisy activity out of truth docs
- keep provenance explicit
- let the orchestrator route work without inventing new storage rules each time

## Core Surfaces

Every repo using this system should separate these surfaces:

| Surface | Role | Mutability |
| --- | --- | --- |
| `REPO.md` | Canonical repo contract, routing ladder, and provenance rules. | rewritten deliberately |
| `AGENTS.md` | Thin compatibility entrypoint for repo-root agent instructions. | rewritten deliberately |
| `CLAUDE.md` | Thin compatibility shim for Claude-oriented repo instructions. | rewritten deliberately |
| `SPEC.md` | Durable project-level truth for Pipit. | rewritten |
| `STATUS.md` | Current accepted operational reality. | rewritten |
| `PLANS.md` | Accepted future direction that is not current truth yet. | rewritten |
| `INBOX.md` | Ephemeral capture waiting for triage. | append then purge |
| `research/` | Curated reusable research and dependency notes. | append by new file |
| `records/decisions/` | Durable decision records with rationale. | append by new file |
| `git commit history` | Canonical execution history through commit-backed `LOG-*` records. | append-only by new commit |
| `skills/` | Required procedural workflows for repeatable agent tasks. | edit by skill |
| `PIPIT_MASTER_ARCHITECTURE.md` | Deep protocol, security, provisioning, and system-design reference. | rewritten deliberately |

`upstream-intake/` is intentionally omitted for now. Pipit depends on upstream projects, but this repo is not being run as a recurring downstream fork-review system.

## Agent Compatibility Files

Some coding agents look for repo-root instruction files such as `AGENTS.md` or `CLAUDE.md`.

When a repo using this model includes them:

- they should act as entrypoints into the canonical rules, not competing policy documents
- they should stay short enough that they do not drift from `REPO.md`
- `AGENTS.md` should be the main editable agent-instructions file when both files exist
- `CLAUDE.md` should be a thin shim that points to `AGENTS.md` when the tool supports it
- `skills/` should ship with adopted repos as repo-native procedural documentation, even when the agent runtime does not auto-load skills
- optional repo subsystems may have optional companion skills

Recommended split:

- `REPO.md`
  - canonical rules
- `AGENTS.md`
  - canonical editable agent-instructions file
- `CLAUDE.md`
  - Claude Code shim that points to `AGENTS.md`
- `skills/<name>/SKILL.md`
  - procedure for one repeatable workflow

## Separation Rules

These boundaries are mandatory:

- `SPEC.md` is not a changelog.
- `STATUS.md` is not a transcript.
- `PLANS.md` is not a brainstorm dump.
- `INBOX.md` is not durable truth.
- `research/` is not raw execution history.
- `records/decisions/` is not the same as git commit history.
- Off-Git memory is not a substitute for repo-local canonical docs.

That separation gives future operators and future agents fast answers to different questions:

- What is the project? -> `SPEC.md`
- What is true right now? -> `STATUS.md`
- What future work is actually accepted? -> `PLANS.md`
- What did we learn from exploration? -> `research/`
- What did we decide and why? -> `records/decisions/`
- What actually happened during execution? -> git commit history via `commit: LOG-*`

## Routing Ladder

When new work arrives, route it in this order:

1. Untriaged capture -> `INBOX.md`
2. Durable project truth -> `SPEC.md`
3. Current operational reality -> `STATUS.md`
4. Accepted future direction -> `PLANS.md`
5. Reusable research or dependency analysis -> `research/`
6. Durable decision with rationale -> `records/decisions/`
7. Execution history -> git commit history via commit-backed `LOG-*` records

One task may legitimately touch more than one surface. Example: a feature kickoff can create a `DEC-*`, update `PLANS.md`, and later land a commit-backed `LOG-*` record if the execution itself changes.

## Capture Packets

Raw external source events are immutable Off-Git events.
Do not treat every raw source event as a separate repo artifact.
Do not treat a full external-tool history as one giant inbox item.

Use capture packets as mutable working envelopes around one or more relevant raw source events.

A capture packet may be:

- appended as new related source events arrive
- edited into a clearer operator-intent summary
- split when it contains multiple independent asks
- merged when several source events are one meaningful thread
- summarized into `INBOX.md` as an `IBX-*`
- routed into durable repo artifacts after triage

Triage should happen per meaningful capture packet.
Routed repo artifacts should copy a short summary, the stable inbox ID, and any needed external provenance handle instead of relying on raw external source staying visible.

## Inbox Pressure Review

`INBOX.md` is an ephemeral scratch disk for untriaged capture.
It is not a backlog, roadmap, brainstorm archive, or project digest.

Run a daily inbox pressure review when the project receives substantial capture.
This review is focus-protecting triage.
It is not an unconditional digest of every random idea.

During the review:

- group related `IBX-*` entries and capture packets into meaningful clusters
- identify stale, duplicate, low-confidence, noisy, or "maybe later" capture
- ask whether each meaningful cluster should route, research, plan, discard, or stay held
- promote only items that survived triage and have an accepted destination
- report counts or clusters of held, discarded, stale, or noisy capture instead of summarizing every low-signal item
- preserve `IBX-*` as a permanent provenance ID even if the inbox line is deleted

Do not update `SPEC.md`, `STATUS.md`, `PLANS.md`, `research/`, or `records/decisions/` directly from raw inbox pressure.
The orchestrator or operator-approved routing step owns promotion.

## Promotion Discipline

Promotion should be sparse.
Do not mirror one evolving thought into every repo surface.

Raw shaping may stay in external capture, generic notes, off-Git capture packets, or `INBOX.md` while the thought is still forming.
Repo artifacts are a refinery: each layer should receive only the part that belongs there, when it is ready.

Use each layer for its distinct job:

- `INBOX.md`
  - ephemeral routed capture
- `research/`
  - reusable exploration, evidence, framing, rejected paths, and open questions
- `records/decisions/`
  - meaningful accepted choices and why the winning choice won
- `PLANS.md`
  - accepted future work that survived triage
- `SPEC.md`
  - concise durable product or system truth after the argument is settled
- `STATUS.md`
  - current operational reality
- git commit history via `commit: LOG-*`
  - canonical execution history, not truth, decision, plan, or research mirrors

A research memo may remain research forever.
A decision record should exist only when a real product, architecture, workflow, trust, upstream, or repo-operating choice has been made.
`SPEC.md`, `STATUS.md`, and `PLANS.md` should receive concise outcomes, not copied debate.

One task may touch multiple layers, but each touched layer must have its own distinct job.

## Roles

### Operator

The operator is the final authority on product direction, acceptance of truth changes, and escalation outcomes.

### Orchestrator

The orchestrator owns routing and synthesis. It may update `SPEC.md`, `STATUS.md`, `PLANS.md`, create research memos, write decisions, and create commit-backed execution records.

### Worker

Workers execute bounded tasks. They should prefer continuing the current relevant `LOG-*` through amend or rebase when the same workstream continues, or creating one only when the execution thread is materially distinct, and should propose truth changes through the orchestrator instead of rewriting canonical docs ad hoc.

### External Capture Surfaces

External capture surfaces are capture and control channels.

They may:

- create or append inbox capture
- request approvals
- deliver summaries
- surface blocked states

They must not write truth docs directly.

## Write Rules

- Update `SPEC.md`, `STATUS.md`, and `PLANS.md` only when the accepted state actually changes.
- Keep `INBOX.md` short-lived and purge entries once they are reflected elsewhere.
- Daily inbox review should reduce pressure by clustering, routing, holding, or purging capture; it should not generate a larger digest by default.
- Put reusable dependency or ecosystem context in `research/`.
- Record durable product, architecture, or workflow choices in `records/decisions/`.
- Record migrations, implementations, and noteworthy execution sessions in git commit history through commit-backed `LOG-*` records.
- Do not invent a parallel execution-history file layer.
- When `PIPIT_MASTER_ARCHITECTURE.md` conflicts with `SPEC.md`, `STATUS.md`, or current code on non-protocol implementation details, treat the architecture document as authoritative for protocol and security only, and prefer the newer project-level docs for repo reality.
- Before editing `research/` or `records/`, read the local directory `README.md` first. If it defines a default section order or canonical example, follow that shape instead of inventing a new one.

## Artifact Writing Rule

Repo-template discipline applies at the artifact level, not only the directory level.

- Prefer one strong local `README.md` per durable artifact directory.
- Treat that guide as binding when it defines scope, default section order, or a canonical example.
- Make the smallest justified deviation when repo-specific truth requires it, and keep the core provenance fields intact.

## Stable IDs

Use these prefixes:

- `IBX-YYYYMMDD-NNN`
- `RSH-YYYYMMDD-NNN`
- `DEC-YYYYMMDD-NNN`
- `LOG-YYYYMMDD-HHMMSS-<agent-suffix>`
- `UPS-YYYYMMDD-NNN` only if `upstream-intake/` is enabled later

Numbering is per day and per artifact type using the least available `NNN` for file-backed artifact types.

File-backed stable-ID-bearing artifacts should include:

- `Opened: YYYY-MM-DD HH-mm-ss KST`
- `Recorded by agent: <agent-id>`

Commit-backed `LOG-*` records live in git commit history and use commit trailers plus structured body keys instead of file openings.

## Commit-Backed Execution Records

After adopting this model, commits should include these trailers:

- `project: pipit`
- `agent: <agent-id>`
- `role: orchestrator|worker|subagent|operator`
- `commit: LOG-YYYYMMDD-HHMMSS-<agent-suffix>[, LOG-...]`

Optional:

- `artifacts: <artifact-id>[, <artifact-id>...]`

Normal commits should use these body keys:

- `timestamp:`
- `changes:`
- `rationale:`
- `checks:`
- optional `notes:`

The first `LOG-*` id is the primary execution id for the commit.
Additional `LOG-*` ids mean the landed commit canonically absorbs earlier execution records whose separate commits will not remain separate landed history.
Merge commits must mint their own primary `LOG-*` id.
`--amend` keeps the same primary `LOG-*` id.
`rebase` keeps the same primary `LOG-*` id.
If cherry-pick relocates work and the original commit will not also land, keep the same primary `LOG-*` id.
If both original and cherry-picked commits could land, the later commit must mint a new primary `LOG-*` id and mention source `LOG-*` ids only in `notes:` if needed.
If a collision is discovered before landing, the later branch renumbers before merge.
`artifacts:` is optional and should reference only related non-`LOG-*` durable artifacts.
Bootstrap or migration exceptions must be explicit in the commit message.

## Commit Provenance Enforcement

Pipit enforces commit provenance through both local hooks and CI:

- Local hook: `.githooks/commit-msg`
- Local validators: `scripts/check-commit-standards.sh` and `scripts/check-commit-range.sh`
- Hook installer: `scripts/install-hooks.sh`
- CI workflow: `.github/workflows/commit-standards.yml`

Use `scripts/install-hooks.sh` to configure `core.hooksPath` for the local clone. Bootstrap or migration exceptions remain valid only when they are explicit in the commit message.

## Skills

The repo-root `skills/` directory is Pipit's required repo-native procedure layer. It complements this document and does not replace it.

Agents should read the relevant workflow even when their runtime does not auto-load skills.

Required baseline skills:

- `skills/repo-orchestrator/SKILL.md`
- `skills/daily-inbox-pressure-review/SKILL.md`

Conditional skills:

- `skills/upstream-intake/SKILL.md` is intentionally omitted unless `upstream-intake/` is enabled later.

Keep skills procedural. Keep repo-wide policy here in `REPO.md`.
