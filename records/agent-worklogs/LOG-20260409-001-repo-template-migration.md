# LOG-20260409-001 Repo-Template Migration

- Opened: `2026-04-09 05-25-28 KST`
- Recorded by agent: `codex-gpt5-20260409-repo-template-migration`

## Summary

Migrated Pipit from the retired `plan/` brief workflow to the repo-template operating model without changing Android, iOS, KMP, or vendor implementation files as part of the staged migration set.

## Inputs Reviewed

- `README.md`
- `.github/copilot-instructions.md`
- `PIPIT_MASTER_ARCHITECTURE.md`
- `iosApp/README.md`
- `plan/01-AGENT_FIRMWARE_ENGINEER.md`
- `plan/02-AGENT_KMP_CORE_DEV.md`
- `plan/03-AGENT_WEB_DASHBOARD_DEV.md`
- `plan/04-AGENT_BLE_PROXIMITY_ENGINEER.md`
- `plan/05-AGENT_ANDROID_USB_ENGINEER.md`
- `plan/06-AGENT_3D_UI_ENGINEER.md`
- `plan/07-AGENT_ONBOARDING_UI_ENGINEER.md`
- `plan/08-AGENT_SETTINGS_UI_ENGINEER.md`
- current git history and current working-tree state

## Work Performed

1. Created the canonical root docs: `repo-operating-model.md`, `SPEC.md`, `STATUS.md`, `PLANS.md`, and `INBOX.md`.
2. Created `research/`, `records/decisions/`, and `records/agent-worklogs/` plus bootstrap artifacts.
3. Routed cross-repo context about Immogen, Whimbrel, Bifrost, and vendored Three.js into `RSH-20260409-001`.
4. Recorded the adoption decision in `DEC-20260409-001`.
5. Updated active guidance in `README.md`, `.github/copilot-instructions.md`, `iosApp/README.md`, and `PIPIT_MASTER_ARCHITECTURE.md` so they reference the canonical surfaces instead of the retired brief workflow.
6. Retired the `plan/` directory after re-homing its durable content into the new truth, plan, research, and record layers.
7. Prepared the repo for provenance-bearing commits using `project: pipit`, the migration `agent:` id, and artifact references.

## Migration Notes

- The old brief set mixed Pipit-local work with external repo context. Only Pipit-local truth and accepted future direction were carried into `SPEC.md`, `STATUS.md`, and `PLANS.md`.
- Historical execution and evaluation notes were not copied wholesale. Git history plus this `LOG-*` file are treated as the durable record after migration.
- The iOS README was updated to reflect the current SwiftUI entry path and bundled viewer implementation rather than the older UIKit-only description.
- The current working tree was already dirty before this migration. The migration was isolated onto `codex/repo-template-migration` and should be committed with targeted staging.

## Follow-Up

- Use the new canonical docs for future routing.
- Keep future dependency drift in new `RSH-*` artifacts.
- Record the first post-migration commit with the required provenance trailers.
