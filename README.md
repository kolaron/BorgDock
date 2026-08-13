# BorgDock

Containerized cold-backup solution using Borgmatic and a removable USB HDD. Powered by docker-borgmatic.

The backup runs via Docker Compose on a configurable schedule (default: 2 AM daily). If the backup disk is not connected, the backup is safely skipped. If the disk is connected, the container detects it, mounts it, runs Borgmatic via S6 Overlay, writes ISO-timestamped logs, and gracefully unmounts the disk when finished or on shutdown.

## Features

- **Borgmatic + BorgBackup** — Industry-standard backup tools
- **Cold/offline backup workflow** — USB-based cold storage
- **Removable USB HDD support** — UUID-based disk detection and mounting
- **Containerized execution** — Docker Compose for portable deployment
- **S6 Overlay** — Production-grade process management with graceful shutdown
- **Signal handling** — In-progress backups complete cleanly on container stop
- **Automatic mount/unmount** — No manual disk management
- **ISO-timestamped logging** — Docker-integrated logs with `docker logs -f`
- **Scheduled or manual** — CRON-based scheduling or one-off backup commands
- **Multi-arch support** — Works on amd64, arm64, and other architectures

## Repository Layout

```text
.
├── README.md                           # This file
├── MIGRATION.md                        # Upgrade guide from bare-metal BorgDock
├── Dockerfile                          # Extends borgmatic with USB mount service
├── docker-compose.yml                  # All-in-one container configuration
├── .dockerignore                       # Clean Docker build context
├── root/
│   ├── init/init-usb-backup/          # S6 USB detection/mount/unmount service
│   │   ├── run                        # Mount USB at startup
│   │   └── finish                     # Unmount USB at shutdown
│   └── etc/borgmatic.d/
│       └── config.yaml                # Borgmatic configuration (env-var substitution)
│
├── scripts/                            # Legacy bare-metal scripts (deprecated)
│   └── borg-run
└── systemd/                            # Legacy systemd files (deprecated)
    ├── borg-cold-backup.service
    └── borg-cold-backup.timer
```

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/kolaron/BorgDock.git
cd BorgDock
```

### 2. Create Docker Secret for Borg Passphrase

Store your Borg repository passphrase securely:

```bash
echo "your-passphrase" | docker secret create borg_passphrase -
```

### 3. Customize Configuration

Copy the environment template:

```bash
cp .env.example .env.local
```

Edit `docker-compose.yml` environment variables:

- **BACKUP_DISK_UUID**: Your USB disk's UUID
- **BORG_SOURCE_1**, **BORG_SOURCE_2**, etc.: Directories to back up
- **TZ**: Your timezone (for logging and scheduling)
- **CRON**: Backup schedule (default: `0 2 * * *` = 2 AM UTC daily)

Get your disk UUID:

```bash
ls -l /dev/disk/by-uuid/ | grep your-disk-label
```

### 3. Build and Start

```bash
docker-compose build
docker-compose up -d
```

### 4. Verify

Check logs:

```bash
docker-compose logs -f
```

Expected output during backup:
```
[2026-08-13T02:00:00] → Mounting backup disk...
[2026-08-13T02:00:02] ✓ Backup disk mounted successfully
[2026-08-13T02:00:03] Starting borgmatic...
[2026-08-13T02:15:45] Backup completed. Archiving done.
[2026-08-13T02:15:46] → Cleanup: Unmounting backup disk...
[2026-08-13T02:15:48] ✓ Backup disk unmounted safely
```

Check if USB is mounted:

```bash
docker-compose exec borgmatic findmnt /mnt/backup
```

## Installation (Detailed)

### Prerequisites

- Docker 20.10+ and Docker Compose 2.0+
- USB backup disk with a known UUID
- fstab entry for USB disk (noauto option)
- Existing Borg repository or willingness to create one
- SSH access to container host (for manual commands)

### fstab Setup

Ensure your USB disk is in `/etc/fstab` with the `noauto` flag (so it doesn't auto-mount):

```fstab
UUID=7be9c515-489c-4cd5-a08c-97ce6dae9d6e /mnt/backup ext4 noauto,nofail,noatime,x-systemd.device-timeout=30s 0 0
```

### Docker Secret

```bash
docker secret create borg_passphrase - <<< "your-passphrase"
```

### docker-compose.yml

Update `docker-compose.yml` with your configuration.

For an existing Borg repository, use the same passphrase:

```yaml
environment:
  BORG_PASSPHRASE_FILE: "/run/secrets/borg_passphrase"
  BACKUP_DISK_UUID: "7be9c515-489c-4cd5-a08c-97ce6dae9d6e"
  BORG_SOURCE_1: "/tank/apps"
  BORG_SOURCE_2: "/tank/home"
  CRON: "0 2 * * *"  # Daily at 2 AM UTC
```

### Start Container

```bash
docker-compose build
docker-compose up -d
docker-compose logs -f
```

### Initialization (First Run)

If creating a new Borg repository:

```bash
# Connect USB disk
# Container will mount it automatically (or manually: docker-compose exec borgmatic mount /mnt/backup)

# Initialize repository
docker-compose exec borgmatic borgmatic rcreate --encryption repokey-blake2 --source-repository /mnt/backup/borg-repo

# Start scheduled backups
docker-compose restart
```

## Configuration

### Environment Variables

All configuration is driven by environment variables in `docker-compose.yml`:

| Variable | Example | Purpose |
|----------|---------|---------|
| `TZ` | `UTC` | Timezone for logging and cron scheduling |
| `BACKUP_DISK_UUID` | `7be9c515-489c-4cd5-a08c-97ce6dae9d6e` | UUID of USB backup disk |
| `BACKUP_MOUNT_PATH` | `/mnt/backup` | Mount point for USB disk |
| `BORG_REPO_PATH` | `/mnt/backup/borg-repo` | Borg repository location |
| `BORG_SOURCE_1`, `_2`, etc. | `/tank/apps` | Directories to back up |
| `BORG_PASSPHRASE_FILE` | `/run/secrets/borg_passphrase` | Path to passphrase (Docker Secret) |
| `BORG_COMPRESSION` | `zstd,8` | Compression algorithm and level |
| `CRON` | `0 2 * * *` | Backup schedule (cron format) |
| `CRON` | `false` | Disable schedule (manual only) |

### Borgmatic Configuration

Edit `root/etc/borgmatic.d/config.yaml` to customize your backup behavior:

- **Source directories** — Use environment variables: `${BORG_SOURCE_1}`, `${BORG_SOURCE_2}`, etc.
- **Retention policy** — keep_daily, keep_weekly, keep_monthly, keep_yearly
- **Exclude patterns** — Which directories/files to skip (e.g., caches, node_modules)
- **Compression** — zstd, lz4, none, etc.
- **Checks** — Repository integrity checks
- **Hooks/Commands** — Pre/post backup orchestration (optional)

#### Adding Orchestration Hooks

To stop/start services before/after backup (e.g., Docker containers, databases, VMs), add a `commands:` section to `config.yaml`:

```yaml
commands:
  - before: everything
    run:
      - 'your-command-here stop'
      - 'another-command here'
  
  - after: everything
    states: [finish, fail]  # Run even if backup fails
    run:
      - 'your-command-here start'
      - 'another-command here'
```

**Example: Docker container with label:**
```yaml
commands:
  - before: everything
    run:
      - 'docker ps -q -f "label=backup" | xargs --no-run-if-empty docker container stop -t 60'
  - after: everything
    states: [finish, fail]
    run:
      - 'docker compose start'
```

**Example: SSH to remote host (Proxmox, etc.):**
```yaml
commands:
  - before: everything
    run:
      - 'ssh -i /root/.ssh/id_ed25519 root@proxmox-host "pct exec 100 -- docker compose stop" || true'
  - after: everything
    states: [finish, fail]
    run:
      - 'ssh -i /root/.ssh/id_ed25519 root@proxmox-host "pct exec 100 -- docker compose start" || true'
```

For SSH examples, ensure SSH key is mounted:
```yaml
# docker-compose.yml
volumes:
  - /root/.ssh:/root/.ssh:ro
```

See [Borgmatic documentation](https://torsion.org/borgmatic/docs/how-to/add-preparation-and-cleanup-steps-to-backups/) for more hook options.

## Usage

### Manual Backup

Run a backup immediately (regardless of schedule):

```bash
docker-compose exec borgmatic borgmatic-start --stats
```

### One-Shot Backup (no schedule)

Disable cron and run manually:

```bash
# In docker-compose.yml, set: CRON: "false"
docker-compose up -d
docker-compose exec borgmatic borgmatic-start --stats
```

### Check Backup Schedule

```bash
docker-compose exec borgmatic borgmatic list --archive-filter newest 5
```

### List Backups in Repository

```bash
docker-compose exec borgmatic borgmatic list
```

### Restore File/Directory

Browse archive and restore:

```bash
# List archive contents
docker-compose exec borgmatic borgmatic list --repository label --archive ARCHIVE_NAME --short

# Restore to /mnt/restore
docker-compose exec borgmatic borg extract \
  /mnt/backup/borg-repo::ARCHIVE_NAME \
  path/to/file \
  --destination /mnt/restore
```

### Monitor Backup Progress

```bash
docker-compose logs -f borgmatic
```

Example output:
```
[2026-08-13T02:00:00] → Mounting backup disk...
[2026-08-13T02:00:02] ✓ Backup disk mounted successfully
[2026-08-13T02:00:03] Starting borgmatic...
[2026-08-13T02:05:12] A cache inconsistency was detected...
[2026-08-13T02:15:45] Backup completed. Archiving done.
[2026-08-13T02:15:46] → Cleanup: Unmounting backup disk...
[2026-08-13T02:15:48] ✓ Backup disk unmounted safely
```

### Graceful Shutdown

```bash
docker-compose down
```

This will:
1. Send SIGTERM to borgmatic
2. Allow in-progress backup to complete (up to `stop_grace_period: 30m`)
3. Unmount USB disk
4. Stop container

**Important**: Do NOT force-kill (`docker kill`) during backup as it may leave the Borg repository locked.

## Monitoring

### Container Logs

```bash
docker-compose logs -f
```

### Backup Completion Status

Check if last backup succeeded:

```bash
docker-compose exec borgmatic borgmatic list --repository label | tail -5
```

### Disk Space

Check USB disk usage:

```bash
docker-compose exec borgmatic df -h /mnt/backup
```

### Health Check

```bash
docker-compose ps
```

Status should show `healthy` in the `STATUS` column if USB is mounted.

## Typical Weekly Workflow

1. **Monday evening**: Connect USB backup disk.
2. **Tuesday 2 AM**: Scheduled backup runs automatically.
   - Container detects disk UUID
   - Mounts disk
   - Stops Docker services (via borgmatic hooks)
   - Runs borgmatic backup
   - Starts services
   - Unmounts disk
3. **Tuesday morning**: Verify completion:
   ```bash
   docker-compose logs | grep "✓ Backup disk unmounted"
   ```
4. **Thursday evening**: Disconnect USB disk and store in safe location.

Repeat weekly.

## Troubleshooting

### USB Disk Not Detected

```bash
# Verify UUID
ls -l /dev/disk/by-uuid/ | grep your-disk

# Check fstab entry
cat /etc/fstab | grep 7be9c515-489c-4cd5-a08c-97ce6dae9d6e

# Manually mount (if needed)
sudo mount /dev/disk/by-uuid/7be9c515-489c-4cd5-a08c-97ce6dae9d6e /mnt/backup
```

### Backup Fails with "Repository is Locked"

This happens if a previous backup crashed without releasing the lock:

```bash
docker-compose exec borgmatic borg break-lock /mnt/backup/borg-repo
docker-compose exec borgmatic borgmatic-start --stats
```

### Container Won't Stop Gracefully

Increase `stop_grace_period` in `docker-compose.yml`:

```yaml
services:
  borgmatic:
    stop_grace_period: 1h  # Give backup up to 1 hour to complete
```

### Out of Disk Space on USB

Check usage:

```bash
docker-compose exec borgmatic du -sh /mnt/backup/borg-repo
docker-compose exec borgmatic df -h /mnt/backup
```

Prune old backups per retention policy:

```bash
docker-compose exec borgmatic borgmatic prune --progress
```

### Passphrase Not Working

Verify Docker Secret:

```bash
docker secret inspect borg_passphrase --pretty
```

Recreate if incorrect:

```bash
docker secret rm borg_passphrase
echo "correct-passphrase" | docker secret create borg_passphrase -
docker-compose restart
```

### Proxmox Container/VM Hooks Not Triggering

If using `pct exec` or `qm guest exec` in borgmatic hooks:

1. Ensure host has Proxmox CLI access from container
2. Mount SSH key into container (optional):
   ```yaml
   volumes:
     - /root/.ssh:/root/.ssh:ro
   ```
3. Check logs:
   ```bash
   docker-compose logs borgmatic | grep -i "before_backup\|after_backup"
   ```

### Permission Denied on /mnt/backup

Container runs as root. Verify mount permissions:

```bash
ls -la /mnt/backup
sudo chmod 755 /mnt/backup
```

## Migration from Bare-Metal BorgDock

See [MIGRATION.md](MIGRATION.md) for detailed upgrade instructions from the original systemd-based BorgDock.

## Architecture

**BorgDock** is built on:

- **docker-borgmatic** — Production-grade borgmatic container with S6 Overlay
- **S6 Overlay** — Init system for graceful process management and signal handling
- **Borgmatic** — Wrapper around Borg Backup for easier automation
- **Borg Backup** — Deduplicating backup tool

## Process Flow

```
Container Start
    ↓
S6 Overlay Init (PID 1)
    ↓
init-envfile service (process Docker Secrets)
    ↓
init-usb-backup service (mount USB disk by UUID)
    ↓
svc-cron service (start crond)
    ↓
Scheduled Backup (2 AM UTC or on-demand)
    ↓
    ├→ borgmatic before_backup hooks (stop services)
    ├→ borgmatic backup (create archive)
    └→ borgmatic after_backup hooks (start services)
    ↓
Container Stop (SIGTERM)
    ↓
S6 Shutdown
    ↓
init-usb-backup finish (unmount USB disk)
    ↓
Container Exit
```

## Security Considerations

- **Secrets**: Borg passphrase stored in Docker Secrets, not in compose file
- **Root user**: Container runs as root (required for mount/unmount)
- **Capabilities**: `SYS_ADMIN` capability required for mount operations
- **SSH keys**: Optional mounting for remote repository access
- **No new privileges**: Container cannot escalate privileges

## Performance

- **First backup**: Full copy of all source directories
- **Subsequent backups**: Only changed blocks (deduplication)
- **Chunk cache**: Stored in volume for faster repeat backups
- **Compression**: zstd,8 by default (adjust `BORG_COMPRESSION` for speed vs. size)

## License

BorgDock extends [docker-borgmatic](https://github.com/borgmatic-collective/docker-borgmatic) (GPL-3.0).

## Support

For issues:

1. Check [docker-borgmatic documentation](https://github.com/borgmatic-collective/docker-borgmatic)
2. Review [Borgmatic docs](https://torsion.org/borgmatic/)
3. Check Borg Backup [README](https://borgbackup.readthedocs.io/)
4. Review logs: `docker-compose logs -f`