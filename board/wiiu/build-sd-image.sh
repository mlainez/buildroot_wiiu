#!/usr/bin/env bash
# Assemble output/images/wiiu-sd.img: an MBR image with a FAT32 boot partition
# (fw.img + linux/) and an ext4 rootfs partition. Uses only unprivileged tools
# (mkfs.vfat + mtools + sfdisk + dd), so it works in containers without root.
#
#   $1            BINARIES_DIR (default <repo>/output/images)
#   WIIU_BOOT_MB  FAT32 boot partition size in MiB (default 256)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARIES_DIR="${1:-$REPO_ROOT/output/images}"
BOOT_MB="${WIIU_BOOT_MB:-256}"

SD_DIR="$BINARIES_DIR/sd"
ROOTFS="$BINARIES_DIR/rootfs.ext2"
OUT="$BINARIES_DIR/wiiu-sd.img"

info() { printf '[sd-image] %s\n' "$*"; }
die()  { printf '[sd-image] ERROR: %s\n' "$*" >&2; exit 1; }

# --- prerequisites ---------------------------------------------------------
for t in sfdisk mkfs.vfat mcopy mmd dd truncate stat; do
  command -v "$t" >/dev/null 2>&1 \
    || die "missing tool '$t' — install: dosfstools mtools util-linux coreutils"
done

# --- resolve inputs --------------------------------------------------------
# fw.img: prefer a freshly built per-console image, else the committed
# prebuilt (common-key) loader that linux-wiiu ships for every console.
if   [ -f "$SD_DIR/fw.img" ];     then FWIMG="$SD_DIR/fw.img"
elif [ -f "$SCRIPT_DIR/fw.img" ]; then FWIMG="$SCRIPT_DIR/fw.img"
else die "no fw.img found (looked in $SD_DIR/fw.img and $SCRIPT_DIR/fw.img)"
fi
[ -f "$ROOTFS" ]      || die "rootfs image not found: $ROOTFS (is BR2_TARGET_ROOTFS_EXT2=y?)"
[ -d "$SD_DIR/linux" ] || die "staged boot dir not found: $SD_DIR/linux (post-image.sh runs first)"

# Aroma/CFW boot overlay (payload.elf, wiiu/environments, wiiu/apps, ...). The
# Wii U boots its CFW from this same card, so its files must share the FAT
# partition with fw.img + linux/. Populate board/wiiu/sdcard/wiiu/ once from a
# working Aroma SD card; without it we build a boot-environment-less card that
# only a console exploited straight to a payload.elf loader can use.
SD_OVERLAY="$SCRIPT_DIR/sdcard"
if [ -d "$SD_OVERLAY/wiiu" ]; then
  info "including Aroma boot overlay from $SD_OVERLAY/wiiu"
else
  info "WARNING: no Aroma overlay at $SD_OVERLAY/wiiu — card won't boot to a menu"
  SD_OVERLAY=""
fi

# --- geometry (512-byte sectors, 1 MiB alignment) --------------------------
SECT=512
P1_START=2048
P1_SIZE=$(( BOOT_MB * 1024 * 1024 / SECT ))
P2_START=$(( P1_START + P1_SIZE ))
RFS_BYTES=$(stat -c %s "$ROOTFS")
P2_SIZE=$(( (RFS_BYTES + SECT - 1) / SECT ))
TOTAL_BYTES=$(( (P2_START + P2_SIZE) * SECT ))

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1. build + populate the FAT32 boot partition image --------------------
FAT="$WORK/boot.fat"
truncate -s "$(( P1_SIZE * SECT ))" "$FAT"
mkfs.vfat -F 32 -n WIIUBOOT "$FAT" >/dev/null
# Aroma boot overlay (creates ::/wiiu, ::/payload.elf-side files, etc.) first.
[ -n "$SD_OVERLAY" ] && mcopy -s -i "$FAT" "$SD_OVERLAY"/wiiu ::/
# Loader + kernel.
mmd   -i "$FAT" ::/linux
mcopy -i "$FAT" "$FWIMG" ::/fw.img
for f in "$SD_DIR"/linux/*; do
  [ -e "$f" ] || continue
  mcopy -i "$FAT" "$f" "::/linux/$(basename "$f")"
done

# --- 2. lay down the whole-disk image + partition table --------------------
truncate -s "$TOTAL_BYTES" "$OUT"
sfdisk --quiet "$OUT" <<EOF
label: dos
unit: sectors
start=$P1_START, size=$P1_SIZE, type=c, bootable
start=$P2_START, size=$P2_SIZE, type=83
EOF

# --- 3. stitch the partitions into place -----------------------------------
dd if="$FAT"    of="$OUT" bs=$SECT seek=$P1_START conv=notrunc status=none
dd if="$ROOTFS" of="$OUT" bs=$SECT seek=$P2_START conv=notrunc status=none

info "wrote $OUT ($(( TOTAL_BYTES / 1024 / 1024 )) MiB)"
info "  p1  FAT32 ${BOOT_MB} MiB  : /fw.img + /linux/   (fw.img: $FWIMG)"
info "  p2  ext4  $(( RFS_BYTES / 1024 / 1024 )) MiB  : rootfs  -> root=/dev/mmcblk0p2"
info "flash:  sudo dd if=$OUT of=/dev/sdX bs=4M conv=fsync status=progress"
