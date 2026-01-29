# Obsidian Backup

Automatic Obsidian vault backup using [restic](https://restic.net/) via macOS LaunchAgents.

## Backup schedule

- **Local backups**: Every hour (`~/.vault-backups`)
- **Remote backups**: Every 4 hours to B2 (if configured)

## Logs

```bash
# Local backup log
tail -f ~/.local/log/vault-backup.log

# Remote backup log
tail -f ~/.local/log/vault-backup-remote.log
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

## Other commands

```bash
# List local snapshots
~/.local/bin/backup-vault.sh --list

# List both local and remote snapshots (if B2 configured)
~/.local/bin/backup-vault.sh --list --remote

# List snapshots using restic directly
restic -r ~/.vault-backups --password-file ~/.config/restic/password snapshots

# Restore latest snapshot
restic -r ~/.vault-backups --password-file ~/.config/restic/password restore latest --target ~/restored-vault
```
