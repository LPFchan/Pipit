# DEC-20260409-002: Enable Commit Provenance Enforcement

Opened: 2026-04-09 06-55-23 KST
Recorded by agent: codex-gpt5-20260409-provenance-enforcement

## Metadata

- Status: accepted
- Deciders: operator, orchestrator
- Related ids: DEC-20260409-001, LOG-20260409-002

## Decision

Enable commit provenance enforcement in Pipit through both local Git hooks and CI, using the repo-template hook and validator flow.

## Context

Pipit already defined commit provenance in `REPO.md`, but those rules were only social expectations. Without local hook enforcement and remote CI checks, contributors could still create non-compliant commits and only discover the mismatch later, or not at all.

The repo also lacked root `AGENTS.md` and `CLAUDE.md` entrypoints, which meant tools looking for repo-root instruction files would miss the commit-message contract unless they happened to read the operating model or `.github/copilot-instructions.md`.

## Options Considered

### Keep Provenance As Docs-Only Guidance

- Upside: no extra hook or CI setup
- Downside: provenance drift remains easy and silent

### Add Local Hook Enforcement Only

- Upside: catches bad commit messages earlier for contributors who install hooks
- Downside: does not protect pushed commits when hooks were never installed or were bypassed

### Add Local Hook And CI Enforcement

- Upside: catches problems early in local workflows and again remotely on pushed or pull-request commit ranges
- Upside: matches repo-template's intended enforcement model
- Downside: requires a one-time hook installation step per clone and an extra CI workflow

## Rationale

Using both local and remote enforcement gives Pipit the smallest gap between the documented provenance rules and what the repo will actually accept. Reusing the repo-template validators keeps the behavior predictable while preserving explicit bootstrap and migration exceptions.

## Consequences

- Pipit now tracks `.githooks/commit-msg`, `scripts/check-commit-standards.sh`, `scripts/check-commit-range.sh`, and `scripts/install-hooks.sh`.
- Pipit now tracks `.github/workflows/commit-standards.yml` to validate pushed and pull-request commit ranges remotely.
- Fresh clones should run `scripts/install-hooks.sh` once to align local behavior with CI.
- `AGENTS.md` and `CLAUDE.md` explicitly require compliant commit messages when hooks or CI are enabled.
- Bootstrap or migration exceptions remain valid only when they are explicit in the commit message.
