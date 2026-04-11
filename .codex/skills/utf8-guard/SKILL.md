# Skill: UTF-8 Guard

## Purpose
Prevent encoding-related breakages (garbled text, broken quotes, syntax errors) when editing scripts and config files.

## When To Use
Use this skill whenever you edit text files in this repo, especially:
- `*.sh`
- `*.php`
- `*.conf`
- `*.md`

## Mandatory Rules
1. Keep files in UTF-8 encoding (no BOM).
2. Do not introduce mixed encodings or invalid byte sequences.
3. After edits, verify syntax for executable scripts when possible.
4. If encoding looks corrupted, stop and rewrite the affected file cleanly in UTF-8.

## Required Checks (Before Commit)
1. Encoding sanity:
   - Open file and confirm readable text (no mojibake like `i?`, `?` artifacts replacing expected chars).
2. Shell syntax (for `*.sh`):
   - `bash -n <file>`
3. Quick grep for suspicious corruption patterns:
   - `rg "i?|?|\?{2,}" <file>`
4. Verify key interpolations are intact:
   - e.g. `${VAR}`, quoted strings, heredoc boundaries.

## Safe Write Pattern (Windows host)
When writing files from PowerShell, force UTF-8 without BOM:
- `[System.IO.File]::WriteAllText(path, content, New-Object System.Text.UTF8Encoding($false))`

## Recovery Procedure
If corruption is detected:
1. Reconstruct file content from known-good logic (not from corrupted bytes).
2. Save in UTF-8 (no BOM).
3. Re-run syntax checks.
4. Only then commit.

## Commit Gate
Never commit if any of these is true:
- Script syntax check fails.
- File shows mojibake/corrupted characters in critical strings.
- Encoding is uncertain.