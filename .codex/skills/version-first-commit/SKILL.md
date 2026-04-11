# Skill: Version-First Commit

## Purpose
Ensure every code commit starts by updating the script version first.

## Scope
Use this skill for this repository, especially when editing `install.sh`.

## Mandatory Rule
Before any commit:
1. Update `SCRIPT_VERSION` in `install.sh`.
2. Stage and verify that version bump is included in the same commit.

If a change does not include a version bump, do not commit.

## Version Format
Use semantic style: `MAJOR.MINOR.PATCH`.

Examples:
- `1.0.1` -> `1.0.2` for fixes
- `1.0.2` -> `1.1.0` for new features
- `1.1.0` -> `2.0.0` for breaking changes

## Execution Checklist (Agent)
1. Identify target file: `install.sh`.
2. Locate `SCRIPT_VERSION="..."`.
3. Decide next version from change type.
4. Edit `SCRIPT_VERSION` first.
5. Apply all other requested changes.
6. Run a quick diff check:
   - `git diff -- install.sh`
   - Confirm `SCRIPT_VERSION` changed.
7. Commit.

## Commit Guard
Before commit, verify staged diff contains `SCRIPT_VERSION` change:
- `git diff --cached -- install.sh | grep SCRIPT_VERSION`

If empty, stop and fix.

## Suggested Commit Message Pattern
- `chore: bump install script version to X.Y.Z`
- or include bump in feature/fix commit when bundled:
  - `fix: <summary> (bump script version to X.Y.Z)`

## Notes
- Keep version bump in the same commit as the functional change.
- Avoid separate delayed version-bump commits unless user explicitly requests it.