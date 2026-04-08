---
name: repo-orchestrator
description: "Route new Pipit work into the correct canonical artifact layer."
argument-hint: "Task, intake item, maintenance request, or summary to route"
---

# Repo Orchestrator

Use this skill with:

- [../../repo-operating-model.md](../../repo-operating-model.md)
- [../../SPEC.md](../../SPEC.md)
- [../../STATUS.md](../../STATUS.md)
- [../../PLANS.md](../../PLANS.md)

## What This Skill Produces

- correctly routed Pipit repo artifacts
- clear separation between truth, plans, research, decisions, and worklogs
- stable IDs plus lightweight provenance
- fewer ad hoc brief or transcript files

## Procedure

1. Classify the work in routing order.
   - Is this untriaged intake?
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

4. Write the artifact with provenance.
   - Include `Opened: YYYY-MM-DD HH-mm-ss KST`
   - Include `Recorded by agent: <agent-id>`

5. Preserve the separation rules.
   - Do not let dependency notes masquerade as project truth.
   - Do not put speculative ideas directly in `PLANS.md`.
   - Do not treat worklogs as decision records.
   - Do not leave durable status trapped in chat-only updates.

6. If the task crosses layers, create multiple artifacts deliberately.
   - Example: `RSH-*` plus `LOG-*`
   - Example: `DEC-*` plus `PLANS.md`
   - Example: `LOG-*` plus `STATUS.md`

7. If Git commits are created, add commit trailers.
   - `project: pipit`
   - `agent: <agent-id>`
   - `role: orchestrator|worker|subagent|operator`
   - `artifacts: <artifact-id>[, <artifact-id>...]`

## Escalation Triggers

Escalate instead of guessing when the work:

- changes durable product or system truth
- changes public contracts or compatibility posture
- changes the repo operating model itself
- overrides a security-sensitive firmware or provisioning constraint

## Quality Bar

- clear routing
- clear provenance
- clean separation of layers
- reusable repo-native artifacts instead of chat-only outcomes
