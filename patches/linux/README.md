# Kernel patches

## 0001-sdhci-of-hlwd-force-PIO-for-wiiu-wifi.patch

Makes the Wii U's built-in WiFi work.

**The problem.** The WiFi chip is wired up like an SD card and talks through the
same kind of controller the console uses for SD cards. Before WiFi can run, the
system uploads a small firmware file into the chip, then reads it back to check
it arrived. On the Wii U that read-back came back wrong — only the first few
bytes were correct and the rest were zeros — so the kernel reported the firmware
as "corrupted" and WiFi never started.

**The cause.** The controller can move data two ways: in bulk by itself (fast,
called DMA), or one small piece at a time done by the CPU (slower, called PIO).
The Wii U WiFi controller's bulk mode is broken — it sends the first piece and
then stops, which is exactly the "first bytes fine, rest zeros" pattern we saw.
The SD-card slot uses an almost identical controller and its bulk mode works
fine, so the problem is specific to the WiFi one.

**The fix.** Tell the kernel to use the slow-but-reliable one-piece-at-a-time
mode (PIO) for the WiFi controller only, leaving the SD-card controller on fast
bulk mode. The two controllers sit at fixed hardware addresses, so the patch
spots the WiFi one by its address (`0x0d080000`) and switches just that one.
WiFi firmware is tiny, so the slower mode costs nothing noticeable.
