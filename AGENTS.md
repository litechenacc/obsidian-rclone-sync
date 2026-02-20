# AGENTS.md

This repository contains Bash scripts for Obsidian vault synchronization.

- `sync_vault.sh`: main bidirectional sync entrypoint (linked to `~/.local/bin/sync_vault`)
- `setup_sync_daemon.sh`: installs/uninstalls user-level systemd timer + watcher

Use this guide when making changes as an autonomous coding agent.

## Scope And Intent

- Keep the project simple: small, readable shell scripts over heavy frameworks.
- Prioritize reliability and safety over clever one-liners.
- Preserve current behavior unless the task explicitly asks for behavior changes.
- Ignore Claude-specific workflow/rules for this repo unless user asks otherwise.

## Environment Assumptions

- Platform: Linux with `systemd --user`.
- Shell: Bash.
- Runtime tools used by scripts: `rclone`, `flock`, `inotifywait`, `systemctl`.
- Vault path assumption: `$HOME/vault`.
- Main executable assumption: `$HOME/.local/bin/sync_vault`.

## Repository Layout

- `sync_vault.sh`
  - Handles locking and `rclone bisync` execution.
  - Detects first-run `--resync` requirement.
  - Appends logs to `$HOME/.vault_sync.log`.
- `setup_sync_daemon.sh`
  - Writes user service units under `$HOME/.config/systemd/user`.
  - Manages install/uninstall lifecycle for timer and watcher.

## Build / Lint / Test Commands

There is no compile/build step in this repo. Use syntax + lint + script-level checks.

- Syntax check all scripts:
  - `bash -n sync_vault.sh setup_sync_daemon.sh`
- Lint all scripts (if shellcheck installed):
  - `shellcheck sync_vault.sh setup_sync_daemon.sh`
- Optional strict lint profile:
  - `shellcheck -S warning sync_vault.sh setup_sync_daemon.sh`
- Format check (if shfmt installed):
  - `shfmt -d sync_vault.sh setup_sync_daemon.sh`
- Apply formatting:
  - `shfmt -w -i 4 -ci sync_vault.sh setup_sync_daemon.sh`

### Running A Single Test (Important)

There is no formal test suite yet, so "single test" means one targeted script check.

- Single-file syntax test:
  - `bash -n sync_vault.sh`
- Single-file lint test:
  - `shellcheck sync_vault.sh`
- Single behavior check (usage path):
  - `./setup_sync_daemon.sh invalid_arg`
  - Expect exit code `1` and usage text.

### Safe Local Integration Test (No Real User State)

When testing install/uninstall logic, isolate `HOME` and stub system tools.

1. Create temporary HOME:
   - `TMP_HOME="$(mktemp -d)"`
2. Provide stubs for `systemctl` and `inotifywait` earlier in `PATH`.
3. Link or copy `sync_vault.sh` to `$TMP_HOME/.local/bin/sync_vault`.
4. Run:
   - `HOME="$TMP_HOME" PATH="<stub-bin>:$PATH" ./setup_sync_daemon.sh install`
   - `HOME="$TMP_HOME" PATH="<stub-bin>:$PATH" ./setup_sync_daemon.sh uninstall`
5. Assert files created/removed under `$TMP_HOME/.config/systemd/user`.

## Coding Standards

These scripts are Bash-first. Follow shell best practices consistently.

### Shebang And Safety

- Use `#!/bin/bash` for Bash scripts in this repo.
- For new scripts, prefer `set -euo pipefail` unless existing control flow relies on manual exit handling.
- If not using `set -e`, explicitly check and branch on exit codes for critical commands.

### Imports / Sourcing

- This repo currently does not use shared sourced files.
- If adding `source` usage:
  - Keep it near the top of the file after constants.
  - Use absolute paths or carefully derived script-relative paths.
  - Validate sourced file existence with a clear error message.

### Formatting

- Use 4-space indentation; avoid tabs.
- Always quote variable expansions unless intentional word splitting is required.
- Use `$(...)` command substitution, not legacy backticks.
- Keep line length readable; wrap long commands with `\` continuation.
- Prefer one logical operation per line.

### Types And Variables (Shell Semantics)

- Treat variables as strings unless using arithmetic contexts.
- Use `local` inside functions for function-scoped variables.
- Use uppercase for script-level constants (`LOCKFILE`, `LOGFILE`, etc.).
- Use descriptive lowercase names for temporary locals (`exit_code`, `output`).
- Initialize variables close to first use when practical.

### Naming Conventions

- File names: lowercase snake_case with `.sh` suffix.
- Function names: verb_noun style (`check_reqs`, `install_daemon`).
- Service unit names should remain consistent with current `vault-sync*` naming.
- Keep command flags explicit and readable rather than densely compacted.

### Conditionals And Tests

- Prefer `[[ ... ]]` for Bash conditionals.
- Use `[ ... ]` only where POSIX-style behavior is intentionally needed.
- Compare exit codes explicitly for critical branches.
- When checking command output for patterns, avoid UUOC-style subshell overuse.

### Error Handling

- Fail fast on missing hard dependencies (`rclone`, `inotifywait`, script path, vault dir).
- Print actionable errors that include missing command/path.
- Return non-zero on real failures; use zero only for intentional no-op paths.
- Log enough context (timestamp + operation + outcome) for postmortem.
- Avoid silently swallowing failures except for intentional cleanup paths.

### Logging

- Keep timestamp format consistent: `%Y-%m-%d %H:%M:%S`.
- Include structured status markers such as `[成功]`, `[錯誤]`, `[系統]`, `[跳過]`.
- Append logs; do not truncate history unless task explicitly requests rotation.
- If introducing new log categories, keep wording concise and grep-friendly.

### Systemd Unit Generation

- Ensure generated unit files are idempotent and deterministic.
- After changing unit content, keep `systemctl --user daemon-reload` in flow.
- Prefer explicit `ExecStart*` commands over nested indirection.
- Be careful with quoting in embedded `bash -c` strings.

## Change Management Rules For Agents

- Do not rewrite script architecture unless requested.
- Preserve Chinese user-facing messages unless task asks for translation.
- Keep compatibility with existing paths (`$HOME/vault`, `~/.local/bin/sync_vault`).
- If introducing new dependencies, document install command in script comments or README.
- When behavior changes, add a short rationale in commit/PR notes.

## Cursor / Copilot Rules

Checked in this repository:

- `.cursor/rules/`: not present
- `.cursorrules`: not present
- `.github/copilot-instructions.md`: not present

If these files are added later, treat their instructions as higher-priority project policy and update this document accordingly.

## Recommended Verification Before Finishing Work

- Run syntax check for modified script(s).
- Run shellcheck on modified script(s).
- If `setup_sync_daemon.sh` changed, test both `install` and `uninstall` in isolated `HOME`.
- If `sync_vault.sh` changed, verify lock behavior and `--resync` fallback path.
- Confirm no hardcoded machine-specific absolute paths were introduced.
