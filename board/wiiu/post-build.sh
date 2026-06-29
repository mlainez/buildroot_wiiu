#!/bin/sh
# Buildroot post-build script — runs after the rootfs is assembled but
# before any image is created. TARGET_DIR is the staging rootfs.
set -eu

TARGET_DIR="$1"

# Mount /boot (SD FAT partition where the kernel lives) so it can be
# updated from userspace after install.
install -d "$TARGET_DIR/boot"
