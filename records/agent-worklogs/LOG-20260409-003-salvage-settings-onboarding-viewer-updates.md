# LOG-20260409-003: Salvage Settings Onboarding And Viewer Updates

Opened: 2026-04-09 07-11-44 KST
Recorded by agent: codex-gpt5-20260409-branch-merge

## Metadata

- Run type: orchestrator
- Goal: bring the useful product changes from `29afc2e` onto `main` without carrying over its non-compliant commit message or machine-local junk
- Related ids: LOG-20260409-002

## Task

Merge the clean repo-template branch into `main`, then transplant the Android, iOS, viewer, and project changes from the side branch as a new compliant commit.

## Scope

- In scope: fast-forward merge of `codex/repo-template-enforcement` into `main`
- In scope: salvage of the tracked Android, iOS, viewer, and project file changes from `29afc2e`
- Out of scope: carrying over `.idea/`, `androidApp/.idea/`, or `.kotlin/` content from the old side branch

## Entry 2026-04-09 07-11-44 KST

- Action: merged `codex/repo-template-enforcement` into `main`, inspected `29afc2e`, and prepared a clean salvage path that excludes IDE metadata and generated Kotlin cache artifacts
- Files touched: `STATUS.md`, `records/agent-worklogs/LOG-20260409-003-salvage-settings-onboarding-viewer-updates.md`
- Checks run: branch comparison, commit inspection, merge-base inspection
- Output: `main` received the repo-template normalization and provenance-enforcement work, and the remaining product changes were queued for a clean provenance-bearing commit
- Blockers: none
- Next: apply the selected tracked product files from `29afc2e`, verify the resulting range still passes commit-provenance checks, and delete the superseded `codex/` branches once merged work is preserved

## Entry 2026-04-09 07-15-00 KST

- Action: restored the tracked Android, iOS, viewer, and project files from `29afc2e` onto `main` without carrying over `.idea/`, `androidApp/.idea/`, or `.kotlin/` content
- Files touched: `Pipit.xcodeproj/project.pbxproj`, `androidApp/`, `assets/viewer.html`, `iosApp/iosApp/`, `tools/material-mapper-materials.js`
- Checks run: `git diff --cached --check`
- Output: the product changes are staged cleanly on top of the repo-template and provenance-enforcement commits
- Blockers: two whitespace issues surfaced in the salvaged files and were corrected before commit
- Next: stage the updated status and worklog files, create a compliant salvage commit, and then prune the obsolete `codex/` branches
