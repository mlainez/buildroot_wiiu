#!/bin/sh
# Buildroot post-image hook: stage the SD boot files (fw.img, kernel, boot
# config) under output/images/sd/, then assemble output/images/wiiu-sd.img.
set -eu

BINARIES_DIR="$1"
SD_DIR="$BINARIES_DIR/sd"

install -d "$SD_DIR/linux"

# Kernel: buildroot copies dtbImage.wiiu to $BINARIES_DIR per
# BR2_LINUX_KERNEL_IMAGE_NAME.
cp "$BINARIES_DIR/dtbImage.wiiu" "$SD_DIR/linux/dtbImage.wiiu"

# Petitboot config — single profile, boots our ext4 rootfs from mmcblk0p2.
cat > "$SD_DIR/linux/petitboot.conf" <<'EOF'
default Buildroot
timeout 5

label Buildroot
  kernel /linux/dtbImage.wiiu
  args   root=/dev/mmcblk0p2 rootwait
EOF

# Old-style boot.cfg as a fallback for non-Petitboot linux-loader builds.
cat > "$SD_DIR/linux/boot.cfg" <<'EOF'
[loader]
default=buildroot

[profile:buildroot]
name=Buildroot
kernel=sdmc:/linux/dtbImage.wiiu
cmdline=root=/dev/mmcblk0p2 rootwait
EOF

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# fw.img: build it from linux-loader when secrets.env supplies the (common,
# all-retail-consoles) Starbuck key + IV. Otherwise use a prebuilt loader
# dropped at board/wiiu/fw.img, if present.
"$SCRIPT_DIR/build-fw-img.sh" "$BINARIES_DIR" || true
if [ ! -f "$SD_DIR/fw.img" ] && [ -f "$SCRIPT_DIR/fw.img" ]; then
  cp "$SCRIPT_DIR/fw.img" "$SD_DIR/fw.img"
  echo "[fw.img] using prebuilt loader (board/wiiu/fw.img)"
fi

# Assemble the single flashable SD image (output/images/wiiu-sd.img).
"$SCRIPT_DIR/build-sd-image.sh" "$BINARIES_DIR"

echo
echo "===================================================================="
echo "Flashable image ready:  $BINARIES_DIR/wiiu-sd.img"
echo
echo "Flash it from a machine/terminal that can see the card:"
echo "    sudo dd if=$BINARIES_DIR/wiiu-sd.img of=/dev/sdX bs=4M conv=fsync status=progress"
echo "  (replace sdX with your card — double-check with lsblk first!)"
echo
echo "Then insert the card in the Wii U and launch via Aroma's CFW booter."
echo "Login: root / wiiu   (HDMI + USB keyboard; GamePad screen stays blank)"
echo "===================================================================="
