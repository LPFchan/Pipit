---
name: repo-orchestrator
description: "Route new Pipit work into the correct canonical artifact layer."
argument-hint: "Task, capture item, maintenance request, or summary to route"
---

# Repo Orchestrator

Use this skill with:

- [../../REPO.md](../../REPO.md)
- [../../SPEC.md](../../SPEC.md)
- [../../STATUS.md](../../STATUS.md)
- [../../PLANS.md](../../PLANS.md)

## What This Skill Produces

- correctly routed Pipit repo artifacts
- clear separation between truth, plans, research, decisions, and worklogs
- stable IDs plus lightweight provenance
- fewer ad hoc brief or external-tool-only files

## Procedure

1. Classify the work in routing order.
   - Is this untriaged capture?
   - Is this durable project truth?
   - Is this current operational reality?
   - Is this accepted future direction?
   - Is this reusable research?
   - Is this a durable decision?
   - Is this execution history?

2. Route it to the correct surface.
   - `INBOX.md`
   - `SPEC.md`
   - `STATUS.md`
   - `PLANS.md`
   - `research/`
   - `records/decisions/`
   - `records/agent-worklogs/`

3. Assign stable IDs when needed.
   - `IBX-*`
   - `RSH-*`
   - `DEC-*`
   - `LOG-*`
   - Use the least available `NNN` for that date and artifact type.
   - Do not create a new `LOG-*` if appending to the current relevant worklog is enough.

4. Write the artifact with provenance.
   - Include `Opened: YYYY-MM-DD HH-mm-ss KST`
   - Include `Recorded by agent: <agent-id>`

5. Preserve the separation rules.
   - Do not let dependency notes masquerade as project truth.
   - Do not put speculative ideas directly in `PLANS.md`.
   - Do not treat worklogs as decision records.
   - Do not leave durable status trapped in external-tool-only updates.

6. If the task crosses layers, create multiple artifacts deliberately.
   - Example: `RSH-*` plus `LOG-*`
   - Example: `DEC-*` plus `PLANS.md`
   - Example: `LOG-*` plus `STATUS.md`
   - Touch multiple layers only when each touched layer has a distinct job.
   - Do not mirror the same evolving thought into every artifact type.

7. If Git commits are created, add commit trailers.
   - `project: pipit`
   - `agent: <agent-id>`
   - `role: orchestrator|worker|subagent|operator`
   - `artifacts: <artifact-id>[, <artifact-id>...]`
   - If commit hooks are enabled, make the commit message pass the local validator before retrying.
   - Prefer referencing and updating an existing relevant `LOG-*` before creating a new one.

8. If the task is recurring upstream maintenance and the optional module is enabled, use `upstream-intake/` instead of inventing a parallel workflow.

9. If the task is daily inbox pressure review, cluster and triage capture before routing it.
   - Do not summarize every inbox item by default.
   - Promote only survived triage.
   - Leave low-signal ideas in held/discarded counts or clusters instead of expanding them into plans.

## Escalation Triggers

Escalate instead of guessing when the work:

- changes durable product or system truth
- changes public contracts or compatibility posture
- changes the repo operating model itself
- overrides a security-sensitive firmware or provisioning constraint

## Quality Bar

- clear routing
- clear provenance
- sparse promotion
- clean separation of layers
- reusable repo-native artifacts instead of external-tool-only outcomes
