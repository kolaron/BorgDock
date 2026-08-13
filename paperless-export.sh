#!/bin/bash
# ============================================================
# Paperless-ngx Exporter – runs document_exporter
# ============================================================
# This script only exports Paperless data to a directory.
# No Borg backup is performed here – that should be done separately.
# ============================================================
# --------  CONFIGURATION  --------
CONTAINER_NAME="paperless-webserver-1"
# --------  RUN EXPORTER  --------
echo "[$(date)] Starting Paperless export"
docker exec "$CONTAINER_NAME" document_exporter \
    --use-filename-format \
    --delete \
    --zip \
    ../export
if [ $? -eq 0 ]; then
    echo "[$(date)] Export completed successfully."
    exit 0
else
    echo "[$(date)] ERROR: Export failed." >&2
    exit 1
fi