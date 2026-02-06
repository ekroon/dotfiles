# Obsidian Backup

Automatic Obsidian vault backup using [restic](https://restic.net/) via macOS LaunchAgents.

## Backup schedule

- **Local backups**: Every hour (`~/.vault-backups`)
- **Remote backups**: Every 4 hours to B2 (if configured)
- **iCloud backups**: Every hour to iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian/restic`)

## Logs

```bash
# Local backup log
tail -f ~/.local/log/vault-backup.log

# Remote backup log
tail -f ~/.local/log/vault-backup-remote.log

# iCloud backup log
tail -f ~/.local/log/vault-backup-icloud.log
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

If B2 is not configured, the remote log will show:

```
Warning: B2 credentials file not found at /Users/erwin/.config/restic/b2-env, skipping remote backup
Backup complete.
```

## Check status

```bash
launchctl list | grep vault-backup
```

Exit code `0` = success, `127` = command not found (PATH issue).

## B2 configuration (optional)

Remote backups are skipped unless you configure B2 credentials.

### 1. Create B2 bucket

1. Sign up at [backblaze.com/b2](https://www.backblaze.com/b2/cloud-storage.html)
2. Create a bucket
3. Create an Application Key with read/write access

### 2. Configure credentials

```bash
cat > ~/.config/restic/b2-env << 'EOF'
export B2_ACCOUNT_ID="your-key-id"
export B2_ACCOUNT_KEY="your-key"
export RESTIC_REPOSITORY_REMOTE="b2:your-bucket:restic"
EOF

chmod 600 ~/.config/restic/b2-env
```

### 3. Initialize repository

```bash
source ~/.config/restic/b2-env
restic -r "$RESTIC_REPOSITORY_REMOTE" --password-file ~/.config/restic/password init
```

### 4. Test

```bash
~/.local/bin/backup-vault.sh --remote --tag test
```

## iCloud configuration (optional)

iCloud backups store a restic repository in iCloud Drive and add a secondary key stored alongside it for password redundancy.

### 1. Create iCloud folder

```bash
mkdir -p "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian"
```

### 2. Create iCloud password file

```bash
openssl rand -base64 48 > "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian/restic-password"
chmod 600 "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian/restic-password"
```

### 3. Initialize repository and add iCloud key

```bash
ICLOUD_REPO="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian/restic"
ICLOUD_PASSWORD_FILE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian/restic-password"

restic -r "$ICLOUD_REPO" --password-file ~/.config/restic/password init
restic -r "$ICLOUD_REPO" --password-file ~/.config/restic/password key add --new-password-file "$ICLOUD_PASSWORD_FILE"
```

### 4. Test

```bash
~/.local/bin/backup-vault.sh --icloud --tag test
```

## Manual backup operations

Scope flags:
- `--local`, `--remote`, `--icloud` select which repositories to operate on
- If you omit all scope flags, local is assumed
- Combine flags to run multiple (for example, `--local --remote`)

```bash
# Manual local backup
~/.local/bin/backup-vault.sh [--local] --tag manual

# Manual iCloud backup
~/.local/bin/backup-vault.sh --icloud --tag manual

# Manual remote backup
~/.local/bin/backup-vault.sh --remote --tag manual

# Manual local + iCloud backup
~/.local/bin/backup-vault.sh --local --icloud --tag manual

# Check repository integrity and stats
~/.local/bin/backup-vault.sh --check --local
~/.local/bin/backup-vault.sh --check --remote
~/.local/bin/backup-vault.sh --check --icloud
~/.local/bin/backup-vault.sh --check --local --remote

# Run a command after backup completes
~/.local/bin/backup-vault.sh --tag manual -- copilot
~/.local/bin/backup-vault.sh --remote -- ~/scripts/notify.sh
~/.local/bin/backup-vault.sh -- echo "Backup done"
```

The `--check` flag verifies repository integrity and shows statistics:
- Checks all snapshots, trees, and blobs for corruption
- Shows file count and total size of latest snapshot
- Use `--check --remote` to verify the B2 repository (add `--local` for both)
- Use `--check --icloud` to verify the iCloud repository (add `--local` for both)

iCloud backups use the local restic password for normal operations, and add a secondary key stored in iCloud (`restic-password`) for recovery.

The `--` syntax runs any command after the backup finishes. Useful for:
- Triggering notifications
- Running cleanup scripts
- Chaining other tools

## List and restore

```bash
# List local snapshots
~/.local/bin/backup-vault.sh --list --local

# List both local and remote snapshots (if B2 configured)
~/.local/bin/backup-vault.sh --list --local --remote

# List iCloud snapshots
~/.local/bin/backup-vault.sh --list --icloud

# List snapshots using restic directly
restic -r ~/.vault-backups --password-file ~/.config/restic/password snapshots

# List iCloud snapshots using restic directly
restic -r "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Backups/Obsidian/restic" --password-file ~/.config/restic/password snapshots

# Restore latest snapshot
restic -r ~/.vault-backups --password-file ~/.config/restic/password restore latest --target ~/restored-vault
```
