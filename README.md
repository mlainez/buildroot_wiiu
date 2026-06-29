# Linux for the Nintendo Wii U

Builds a bootable SD card with Linux for the Wii U — the console's own mode, not
the built-in Wii (vWii). Uses the [linux-wiiu] kernel (Linux 6.6, all 3 cores).

## You provide two things

This repo has everything except two console-specific files you add yourself:

1. **`board/wiiu/fw.img`** — the small program that starts Linux. Build it (see
   [The loader](#the-loader-fwimg)) or drop in one you already have.
2. **`board/wiiu/sdcard/wiiu/`** — a working **Aroma** setup so the card can
   start that program. Copy the `wiiu/` folder from an Aroma SD card (set up with
   the [Wii U hacking guide][hacks-guide]; get Aroma at [aroma.foryour.cafe]).

## Build

```sh
git clone --recurse-submodules <repo>
# build fw.img first if you don't have one (see below)
make -C buildroot O=$(pwd)/output BR2_EXTERNAL=$(pwd) wiiu_defconfig
make -C buildroot O=$(pwd)/output
```

You get `output/images/wiiu-sd.img`, a ready-to-flash SD card image.

## The loader (fw.img)

`fw.img` is the small program the Wii U runs to start Linux. It has to be
encrypted with two values — the **Starbuck key and IV** — that are the **same on
every retail Wii U**, so one `fw.img` works on all of them. Get the two values
from the [linux-loader] README (or read them from your own console with
[Dumpling]), then:

```sh
cp secrets.env.example secrets.env   # paste the key and IV here
```

`make` then builds `fw.img` for you. You need one of: devkitARM, podman, or
docker (podman and docker download a ready-made build environment automatically).

Already have a `fw.img`? Put it at `board/wiiu/fw.img` and the build uses it
as-is.

## Flash and boot

```sh
sudo dd if=output/images/wiiu-sd.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Put the card in the Wii U and start it from Aroma. Hold **B** on the GamePad for
the boot menu. Log in as `root` / `wiiu` on an HDMI screen with a USB keyboard.

## WiFi

The built-in WiFi works. The fix for the Wii U's WiFi controller (its DMA
engine corrupts transfers, so the kernel forces it to PIO) is already in the
`rewrite-6.6` kernel; the firmware (from [linux-firmware]) is included here.
Connect with:

```sh
nmcli device wifi connect "network name" password "password"
```

(or run `nmtui` for a menu). A USB Ethernet adapter also works and gets an
address automatically.

## Limits

- No graphics acceleration (plain 2D framebuffer only).
- The included WiFi settings use a shared, non-unique MAC address.
- The GamePad screen shows only boot text — log in on an HDMI screen.

## Built with

- Buildroot 2026.05
- [linux-wiiu] kernel (`rewrite-6.6`, Linux 6.6.106) + SMP patches for all 3 cores
- A prebuilt PowerPC toolchain ([nerves_toolchain_wiiu_ppc][toolchain]),
  downloaded during the build.

[linux-wiiu]: https://gitlab.com/linux-wiiu/linux-wiiu
[linux-loader]: https://gitlab.com/linux-wiiu/linux-loader
[toolchain]: https://github.com/mlainez/nerves_toolchain_wiiu_ppc
[linux-firmware]: https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/brcm
[hacks-guide]: https://wiiu.hacks.guide
[aroma.foryour.cafe]: https://aroma.foryour.cafe
[Dumpling]: https://github.com/emiyl/dumpling
