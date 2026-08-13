# BorgDock

Automated cold-backup solution using Borgmatic and a removable USB HDD.

The backup runs via a nightly systemd timer. If the backup disk is not connected, the run is skipped. If the disk is connected, the script mounts it, runs Borgmatic in the under systemd, writes logs, and safely unmounts the disk when finished.

## Features

- Borgmatic + BorgBackup
- Cold/offline backup workflow
- Removable USB HDD support
- Backup disk detection by UUID
- systemd-managed execution
- Automatic mount/unmount
- Automatic logging
- systemd service and timer
- Install, update, uninstall, and status commands

## Repository Layout

```text
.
├── README.md
├── install.sh
├── scripts/
│   └── borg-run
└── systemd/
    ├── borg-cold-backup.service
    └── borg-cold-backup.timer
```

## Installation

Install or update:

```bash
./install.sh
```

Show status:

```bash
./install.sh --status
```

Uninstall:

```bash
./install.sh --uninstall
```

The installer will:

- Install `/usr/local/bin/borg-run`
- Install `borg-cold-backup.service`
- Install `borg-cold-backup.timer`
- Reload systemd
- Enable the timer

## Source Files

### Script

Source:

```text
scripts/borg-run
```

Installed as:

```text
/usr/local/bin/borg-run
```

### Service

Source:

```text
systemd/borg-cold-backup.service
```

Installed as:

```text
/etc/systemd/system/borg-cold-backup.service
```

### Timer

Source:

```text
systemd/borg-cold-backup.timer
```

Installed as:

```text
/etc/systemd/system/borg-cold-backup.timer
```

## Configuration

### Backup Disk UUID

```text
7be9c515-489c-4cd5-a08c-97ce6dae9d6e
```

### Mount Point

```text
/mnt/backup
```

### Example fstab Entry

```fstab
UUID=7be9c515-489c-4cd5-a08c-97ce6dae9d6e /mnt/backup ext4 noauto,nofail,noatime,x-systemd.device-timeout=30s 0 0
```

### Borgmatic Configuration

```text
/etc/borgmatic/config.yaml
```

Repository:

```text
/mnt/backup/borg-repo
```

## Usage

Run a backup manually:

```bash
borg-run
```

Run the scheduled job immediately:

```bash
systemctl start borg-cold-backup.service
```

Note: `systemctl start` blocks until the backup finishes, because the service runs Borgmatic in the foreground. Use `systemctl start --no-block borg-cold-backup.service` to return immediately.

## Monitoring

Show timer schedule:

```bash
systemctl list-timers borg-cold-backup.timer
```

Show timer status:

```bash
systemctl status borg-cold-backup.timer
```

Show service logs:

```bash
journalctl -u borg-cold-backup.service -f
```

List backup logs:

```bash
ls -lt /var/log/borgmatic/
```

Follow the latest backup log:

```bash
tail -f "$(ls -t /var/log/borgmatic/*.log | head -n1)"
```

Check whether a backup is running:

```bash
systemctl is-active borg-cold-backup.service
```

`active` means a backup is in progress; `inactive` means none is running.

## Typical Weekly Workflow

1. Connect the backup HDD.
2. Leave it connected overnight.
3. The timer runs at 02:30.
4. `borg-run` verifies the backup disk UUID.
5. Docker services are stopped by Borgmatic hooks.
6. Borgmatic creates a backup.
7. Docker services are started again.
8. The backup disk is synced and unmounted.
9. Verify:

```bash
findmnt /mnt/backup
```

If no output is returned, the disk is safely unmounted and can be disconnected.

## Uninstall

```bash
./install.sh --uninstall
```

The following data is intentionally preserved:

```text
/var/log/borgmatic/
/etc/borgmatic/
/mnt/backup/borg-repo/
```

## Troubleshooting

Check timer:

```bash
systemctl status borg-cold-backup.timer
```

Check service:

```bash
systemctl status borg-cold-backup.service
```

Check service logs:

```bash
journalctl -u borg-cold-backup.service
```

Note: `journalctl` shows the service lifecycle (start/stop). Detailed backup output is written to the per-run log file in `/var/log/borgmatic/`.

Verify backup disk UUID:

```bash
ls -l /dev/disk/by-uuid/
```

Expected UUID:
```text
7be9c515-489c-4cd5-a08c-97ce6dae9d6e
```

Verify mount status:

```bash
findmnt /mnt/backup
```

Check the latest backup log

```bash
tail -f "$(ls -t /var/log/borgmatic/*.log | head -n1)"
```