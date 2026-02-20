# obsidian-rclone-sync

Reliable bidirectional sync for an Obsidian vault using `rclone bisync`, a systemd timer, and an inotify watcher.

## Workflow

My daily flow looks like this:

1. I keep my vault in `~/vault` on Linux.
2. `sync_vault.sh` runs on a 15-minute timer and also on file changes.
3. I use the DriveSync app on Android to sync the same Google Drive folder locally on my phone.
4. Obsidian on both sides reads the local vault, and rclone handles cloud sync.

Android setup uses DriveSync (https://metactrl.com/).

## Sync Mechanism (Detailed)

- **Locking:** `sync_vault.sh` uses `flock` on `/tmp/rclone_vault_sync.lock` to ensure only one sync runs at a time.
- **Primary operation:** `rclone bisync` runs between `gd:vault` (remote) and `~/vault` (local).
- **Conflict policy:** `--conflict-resolve newer` keeps the newest file on conflict.
- **Empty folders:** `--create-empty-src-dirs` preserves empty directory structure for Obsidian.
- **Resilience:** `--resilient` makes the sync tolerate minor errors.
- **First run handling:** if rclone indicates `--resync` is required, the script logs the initial failure output and automatically retries with `--resync`.
- **Logging:** all activity is appended to `~/.vault_sync.log` with timestamps and status markers.

### Systemd Units

`setup_sync_daemon.sh` writes user-level unit files to `~/.config/systemd/user`:

- `vault-sync.service`: oneshot service that executes `~/.local/bin/sync_vault`.
- `vault-sync.timer`: runs the service every 15 minutes (plus 5 minutes after boot).
- `vault-sync-watcher.service`: on login, runs a sync; then watches `~/vault` with inotify and triggers a sync after changes; on logout, runs a final sync.

The watcher ignores Obsidian workspace noise (`.obsidian/workspace*`) to reduce sync churn.

## Prerequisites

- Linux with `systemd --user` support.
- `rclone` installed and configured with a remote named `gd`.
  - Example target path used by this repo: `gd:vault`.
- `inotifywait` installed (`inotify-tools` package).
- Local vault path at `~/vault`.
- The sync script linked as `~/.local/bin/sync_vault`.

## Setup

1. Link the sync script:

```bash
ln -sf "$PWD/sync_vault.sh" "$HOME/.local/bin/sync_vault"
```

2. Install and start the systemd services:

```bash
./setup_sync_daemon.sh install
```

3. Check status:

```bash
systemctl --user status vault-sync-watcher.service
systemctl --user list-timers
```

## Logs

All sync logs are appended to:

`~/.vault_sync.log`
