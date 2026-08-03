# Obsidian Backup

Work Obsidian vault backup using [restic](https://restic.net/). It runs only on machines with the `work` machine profile and reads the vault from `~/develop/github.com/github/ekroon/obsidian`.

## Table of contents

- [Backup schedule](#backup-schedule)
- [Logs](#logs)
- [Check status](#check-status)
- [Local password configuration](#local-password-configuration)
- [Manual backup operations](#manual-backup-operations)
- [List and restore](#list-and-restore)

## Backup schedule

- **Local backups**: Every hour on work Macs (`~/.vault-backups`)
- **Remote backups**: Disabled
- **iCloud backups**: Disabled

## Logs

```bash
# Local backup log
tail -f ~/.local/log/vault-backup.log
```

A successful backup looks like:

```
Backing up vault to local repository...
using parent snapshot 1e70e98b

Files:           0 new,     0 changed,   215 unmodified
Dirs:            0 new,     0 changed,    82 unmodified
Added to the repository: 0 B (0 B stored)

processed 215 files, 16.216 MiB in 0:00
snapshot abc12345 saved
Pruning old local snapshots...
...
Backup complete.
```

## Check status

```bash
launchctl list | grep vault-backup
```

Exit code `0` = success, `127` = command not found (PATH issue).

## Local password configuration

Local backups use a restic password file at `~/.config/restic/password`. Create it once and keep permissions locked down.

```bash
mkdir -p ~/.config/restic
openssl rand -base64 48 > ~/.config/restic/password
chmod 600 ~/.config/restic/password
```

Initialize the local repository (first time only):

```bash
restic -r ~/.vault-backups --password-file ~/.config/restic/password init
```

The remote and iCloud backup implementations remain in the script for possible future reuse, but the work-vault guard prevents using them.

## Manual backup operations

The work vault supports local backups only. Omit the scope flag or use `--local`; `--remote` and `--icloud` are rejected.

```bash
# Manual local backup
~/.local/bin/backup-vault.sh [--local] --tag manual

# Check repository integrity and stats
~/.local/bin/backup-vault.sh --check --local

# Run a command after backup completes
~/.local/bin/backup-vault.sh --tag manual -- copilot
~/.local/bin/backup-vault.sh -- echo "Backup done"
```

The `--check` flag verifies repository integrity and shows statistics:
- Checks all snapshots, trees, and blobs for corruption
- Shows file count and total size of latest snapshot

The `--` syntax runs any command after the backup finishes. Useful for:
- Triggering notifications
- Running cleanup scripts
- Chaining other tools

## List and restore

```bash
# List local snapshots
~/.local/bin/backup-vault.sh --list --local

# List snapshots using restic directly
restic -r ~/.vault-backups --password-file ~/.config/restic/password snapshots

# Restore latest snapshot
restic -r ~/.vault-backups --password-file ~/.config/restic/password restore latest --target ~/restored-vault
```

## Troubleshooting

### Stale lock errors

If prune fails with "repository is already locked", a previous restic process was likely interrupted:

```bash
# Clear stale locks on local repo
restic -r ~/.vault-backups --password-file ~/.config/restic/password unlock
```

The script automatically clears stale locks before pruning and uses `--retry-lock 2m` to handle transient lock contention.
