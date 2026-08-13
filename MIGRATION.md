# Migration Guide: Bare-Metal BorgDock → Containerized BorgDock

This guide helps you migrate from the original systemd-based BorgDock to the new containerized version based on docker-borgmatic.

## Why Migrate?

| Aspect | Bare-Metal | Containerized |
|--------|-----------|--------------|
| **Installation** | Manual systemd setup | Single `docker-compose up` |
| **Process Management** | Basic systemd (no signal handling) | S6 Overlay (graceful shutdown) |
| **Logging** | File-based (`/var/log/borgmatic/`) | Docker logs (searchable, rotatable) |
| **Portability** | Linux host-specific | Any Docker host (cloud, Podman, Kubernetes) |
| **Dependencies** | System borgmatic + borg packages | Isolated in container |
| **Updates** | Manual binary updates | Image rebuild or pull |
| **Graceful shutdown** | Risk of stale borg locks | Guaranteed clean exit |
| **Secrets** | Hardcoded in config or env | Docker Secrets (secure) |

## Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- Same Borg repository (we'll keep it and its passphrase)
- USB backup disk with fstab entry

## Step-by-Step Migration

### 1. Backup Current Configuration

Save your current setup:

```bash
# Backup borgmatic config
sudo cp /etc/borgmatic/config.yaml /tmp/borgmatic-config.yaml.bak

# Backup any custom hooks
sudo cp -r /etc/borgmatic/ /tmp/borgmatic-backup/

# Record passphrase securely (you'll need it)
# Do NOT print it; just verify you have it stored safely
```

### 2. Prepare Docker Environment

Ensure Docker is running:

```bash
docker --version
docker-compose --version
```

### 3. Clone/Download New BorgDock

```bash
cd /opt
git clone https://github.com/kolaron/BorgDock.git borgdock-docker
cd borgdock-docker
```

Or update if already cloned:

```bash
cd /opt/borgdock-docker
git pull origin main
```

### 4. Create Docker Secret for Passphrase

```bash
# Create secret with your Borg passphrase
echo "your-existing-passphrase" | docker secret create borg_passphrase -
```

Verify:

```bash
docker secret inspect borg_passphrase
```

### 5. Configure docker-compose.yml

Edit `docker-compose.yml` to match your setup:

```bash
cd /opt/borgdock-docker
nano docker-compose.yml
```

Update these sections:

**a. USB Disk Configuration**
```yaml
BACKUP_DISK_UUID: "your-actual-uuid"
BACKUP_MOUNT_PATH: "/mnt/backup"
```

Find your UUID:
```bash
ls -l /dev/disk/by-uuid/ | grep your-disk-label
```

**b. Backup Sources**
```yaml
BORG_SOURCE_1: "/tank/apps"
BORG_SOURCE_2: "/tank/home"
# Add more as needed
```

**c. Backup Schedule**
```yaml
CRON: "0 2 * * *"  # 2 AM UTC daily (adjust TZ if needed)
```

**d. Timezone**
```yaml
TZ: "UTC"  # Change to your timezone
```

### 6. Migrate borgmatic Config (Optional)

The new setup includes a template config at `root/etc/borgmatic.d/config.yaml`. You can:

**Option A: Use provided template** (recommended for fresh start)
- Edit `root/etc/borgmatic.d/config.yaml` with your preferences
- Retention policy, compression, exclude patterns

**Option B: Port existing config**
- Copy your `borgmatic-config.yaml.bak` to `root/etc/borgmatic.d/config.yaml`
- Update environment variable references (see config template for examples)
- Verify syntax: `docker-compose exec borgmatic borgmatic validate --show`

### 7. Stop Old Systemd-Based Backup

```bash
# Stop timer and service
sudo systemctl stop borg-cold-backup.timer
sudo systemctl stop borg-cold-backup.service
sudo systemctl disable borg-cold-backup.timer

# Verify stopped
sudo systemctl status borg-cold-backup.timer
```

**Do NOT uninstall yet** — we want to verify the new container works first.

### 8. Build and Start Container

```bash
cd /opt/borgdock-docker

# Build image
docker-compose build

# Start container in background
docker-compose up -d

# Check logs
docker-compose logs -f
```

Wait for startup to complete (you'll see USB mount messages):

```
[2026-08-13T14:30:00] → Mounting backup disk...
[2026-08-13T14:30:02] ✓ Backup disk mounted successfully
```

### 9. Run Test Backup

Trigger a manual backup to verify everything works:

```bash
docker-compose exec borgmatic borgmatic-start --stats
```

Monitor progress:

```bash
docker-compose logs -f
```

Watch for:
- ✓ USB disk mounted
- borgmatic before_backup hooks run
- Backup completes with archive count
- borgmatic after_backup hooks run
- ✓ USB disk unmounted safely

### 10. Verify Backup Repository

Check that backups are being created in the existing repository:

```bash
docker-compose exec borgmatic borgmatic list --repository label
```

Should show your new archives alongside old ones (e.g., `hostname-20260813-143000`).

### 11. Stop and Remove Old Setup (Optional)

Once you're confident the container is working:

```bash
# Disable old systemd timer
sudo systemctl disable borg-cold-backup.timer
sudo systemctl disable borg-cold-backup.service

# Optionally remove old files
sudo rm /usr/local/bin/borg-run
sudo rm /etc/systemd/system/borg-cold-backup.*
sudo systemctl daemon-reload

# Keep systemd logs archived (optional):
sudo journalctl -u borg-cold-backup.service --since "2000-01-01" --until "now" > /tmp/borg-systemd-logs.txt
```

**Important**: Keep `/etc/borgmatic/config.yaml`, `/mnt/backup/`, and backup logs if needed for reference.

### 12. Schedule Container Auto-Start (Optional)

If you want the container to start automatically on host boot:

```bash
# In docker-compose.yml, ensure this is set:
services:
  borgmatic:
    restart: unless-stopped
```

Then reboot to verify:

```bash
sudo systemctl reboot
sleep 30  # Wait for boot
docker-compose ps  # Container should be running
docker-compose logs -f  # Verify operations
```

## Verification Checklist

- [ ] Docker Secret created: `docker secret inspect borg_passphrase`
- [ ] docker-compose.yml configured with your UUID, sources, timezone
- [ ] Container built: `docker-compose build`
- [ ] Container starts: `docker-compose up -d` (no errors in logs)
- [ ] USB disk detects and mounts: `docker-compose logs | grep "✓ Backup"`
- [ ] Manual backup succeeds: `docker-compose exec borgmatic borgmatic-start --stats`
- [ ] Backup appears in repository: `docker-compose exec borgmatic borgmatic list`
- [ ] Container gracefully stops: `docker-compose down` (no errors)
- [ ] USB disk unmounts cleanly: `docker-compose logs | grep "✓ Backup disk unmounted"`
- [ ] Scheduled backup runs at cron time (wait 24 hours or adjust CRON for testing)

## Rollback to Bare-Metal (If Needed)

If you need to revert:

```bash
# Stop container
docker-compose down

# Re-enable systemd timer
sudo systemctl enable borg-cold-backup.timer
sudo systemctl start borg-cold-backup.timer

# Verify
sudo systemctl status borg-cold-backup.timer
```

Your Borg repository remains intact (Docker container didn't touch it).

## Differences You'll Notice

| Old | New |
|-----|-----|
| Logs in `/var/log/borgmatic/*.log` | Logs via `docker logs -f` |
| Manual run: `borg-run` | Manual run: `docker-compose exec borgmatic borgmatic-start --stats` |
| Schedule: systemd timer | Schedule: CRON env var (managed by docker-borgmatic crond) |
| Passphrase in `/etc/borgmatic/config.yaml` | Passphrase in Docker Secret |
| Manual mount/unmount | Automatic mount/unmount (if disk connected) |
| No signal handling | Graceful shutdown (backup completes before stop) |
| Host-specific setup | Portable (works on any Docker host) |

## Troubleshooting Migration

### Container won't start

```bash
docker-compose logs
# Check for: UUID not found, passphrase error, config syntax
```

### Borg repository locked

```bash
docker-compose exec borgmatic borg break-lock /mnt/backup/borg-repo
```

### USB disk not detected

```bash
# Verify UUID matches what you set
ls -l /dev/disk/by-uuid/

# Verify fstab entry
cat /etc/fstab | grep $(docker-compose exec borgmatic sh -c 'echo $BACKUP_DISK_UUID')

# Try manual mount
sudo mount /mnt/backup
```

### Backup didn't run at scheduled time

```bash
# Check CRON env var
docker-compose exec borgmatic sh -c 'echo $CRON'

# Verify container is running
docker-compose ps

# Check logs
docker-compose logs | tail -50
```

## Support

- **docker-borgmatic docs**: https://github.com/borgmatic-collective/docker-borgmatic
- **Borgmatic docs**: https://torsion.org/borgmatic/
- **Borg Backup docs**: https://borgbackup.readthedocs.io/

## Next Steps

After successful migration:

1. Monitor first few scheduled backups (check logs daily)
2. Test restore process (recover a file to verify backups are good)
3. Update backup documentation/runbooks
4. Consider setting up monitoring/alerts:
   - Health check notifications
   - Backup completion confirmation
   - Error alerts (optional: healthchecks.io, ntfy, etc.)

---

**Welcome to containerized BorgDock! 🐳**
