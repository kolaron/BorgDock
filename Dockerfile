FROM borgmatic/borgmatic:latest

# BorgDock: Cold-backup variant of docker-borgmatic
# Adds S6 service for USB disk detection and mounting

# Copy USB backup initialization service
COPY root/init/init-usb-backup/ /etc/s6-overlay/s6-rc.d/init-usb-backup/

# Copy example borgmatic config
COPY root/etc/borgmatic.d/ /etc/borgmatic.d/

# Ensure S6 service is marked as oneshot
RUN echo "oneshot" > /etc/s6-overlay/s6-rc.d/init-usb-backup/type

# Build S6 dependencies (USB mount must run before cron)
RUN s6-rc-compile /var/cache/s6-rc /etc/s6-overlay/s6-rc.d/

LABEL maintainer="BorgDock" \
      description="Cold-backup borgmatic variant with USB disk support" \
      version="1.0"
