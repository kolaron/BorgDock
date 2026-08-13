#!/bin/bash
set -euo pipefail

APP_NAME="borg-cold-backup"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BORG_RUN_SRC="$REPO_DIR/scripts/borg-run"
SERVICE_SRC="$REPO_DIR/systemd/borg-cold-backup.service"
TIMER_SRC="$REPO_DIR/systemd/borg-cold-backup.timer"

BORG_RUN_DST="/usr/local/bin/borg-run"
SERVICE_DST="/etc/systemd/system/borg-cold-backup.service"
TIMER_DST="/etc/systemd/system/borg-cold-backup.timer"

LOG_DIR="/var/log/borgmatic"

SERVICE_NAME="borg-cold-backup.service"
TIMER_NAME="borg-cold-backup.timer"

usage() {
    cat <<EOF
Usage:
  ./install.sh              Install or update Borg cold backup automation
  ./install.sh --install    Same as default install
  ./install.sh --uninstall  Remove installed automation files
  ./install.sh --status     Show timer, service, process and logs status
  ./install.sh --help       Show this help

Installed files:
  $BORG_RUN_DST
  $SERVICE_DST
  $TIMER_DST

Kept on uninstall:
  $LOG_DIR
  /etc/borgmatic
  /mnt/backup/borg-repo
EOF
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
}

check_source_files() {
    local missing=0

    for file in "$BORG_RUN_SRC" "$SERVICE_SRC" "$TIMER_SRC"; do
        if [ ! -f "$file" ]; then
            echo "Missing source file: $file"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo
        echo "Expected repo structure:"
        echo "  scripts/borg-run"
        echo "  systemd/borg-cold-backup.service"
        echo "  systemd/borg-cold-backup.timer"
        exit 1
    fi
}

install_app() {
    require_root
    check_source_files

    echo "Installing $APP_NAME..."

    echo "Installing borg-run..."
    install -m 0755 "$BORG_RUN_SRC" "$BORG_RUN_DST"

    echo "Installing systemd service..."
    install -m 0644 "$SERVICE_SRC" "$SERVICE_DST"

    echo "Installing systemd timer..."
    install -m 0644 "$TIMER_SRC" "$TIMER_DST"

    echo "Creating log directory..."
    mkdir -p "$LOG_DIR"
    chmod 0755 "$LOG_DIR"

    echo "Reloading systemd..."
    systemctl daemon-reload

    echo "Enabling timer..."
    systemctl enable --now "$TIMER_NAME"

    echo
    echo "Installation complete."
    echo
    echo "Next scheduled run:"
    systemctl list-timers "$TIMER_NAME" --no-pager || true

    echo
    echo "Useful commands:"
    echo "  systemctl start $SERVICE_NAME"
    echo "  systemctl list-timers $TIMER_NAME"
    echo "  journalctl -u $SERVICE_NAME -f"
    echo "  tail -f \"\$(ls -t $LOG_DIR/*.log | head -n1)\""
}

uninstall_app() {
    require_root

    echo "Uninstalling $APP_NAME..."

    echo "Disabling timer..."
    systemctl disable --now "$TIMER_NAME" 2>/dev/null || true

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo
        echo "A backup still appears to be running."
        echo
        echo "Check it with:"
        echo "  systemctl status $SERVICE_NAME"
        echo
        echo "Uninstall stopped to avoid interrupting an active backup."
        echo "Stop the backup manually if needed, then rerun:"
        echo "  ./install.sh --uninstall"
        exit 1
    fi

    echo "Stopping service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    echo "Removing installed files..."
    rm -f "$BORG_RUN_DST"
    rm -f "$SERVICE_DST"
    rm -f "$TIMER_DST"

    echo "Reloading systemd..."
    systemctl daemon-reload
    systemctl reset-failed "$SERVICE_NAME" "$TIMER_NAME" 2>/dev/null || true

    echo
    echo "Uninstall complete."
    echo
    echo "Kept intentionally:"
    echo "  $LOG_DIR"
    echo "  /etc/borgmatic"
    echo "  /mnt/backup/borg-repo"
    echo
    echo "Remove logs manually if wanted:"
    echo "  rm -rf $LOG_DIR"
}

status_app() {
    echo "$APP_NAME status"
    echo

    echo "Timer:"
    systemctl status "$TIMER_NAME" --no-pager 2>/dev/null || true

    echo
    echo "Next run:"
    systemctl list-timers "$TIMER_NAME" --no-pager 2>/dev/null || true

    echo
    echo "Service:"
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || true

    echo
    echo "Backup process:"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        PID="$(systemctl show "$SERVICE_NAME" -p MainPID --value)"
        ps -fp "$PID"
    else
        echo "No backup currently running."
    fi

    echo
    echo "Latest logs:"
    if ls "$LOG_DIR"/*.log >/dev/null 2>&1; then
        ls -lt "$LOG_DIR"/*.log | head
    else
        echo "No logs found in $LOG_DIR"
    fi
}

ACTION="${1:---install}"

case "$ACTION" in
    --install)
        install_app
        ;;
    --uninstall)
        uninstall_app
        ;;
    --status)
        status_app
        ;;
    --help|-h)
        usage
        ;;
    *)
        echo "Unknown option: $ACTION"
        echo
        usage
        exit 1
        ;;
esac
