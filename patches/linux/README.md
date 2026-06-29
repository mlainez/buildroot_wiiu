# Kernel patches

These are applied on top of the pinned `rewrite-6.6` kernel (see
`configs/wiiu_defconfig`). They add SMP — running Linux on all 3 Espresso
cores — which lives only on linux-wiiu's `rewrite-6.6-smp` branch. That branch
trails `rewrite-6.6` by ~26 LTS releases and lacks the WiFi fix, so instead of
using it we track `rewrite-6.6` and carry just its two SMP commits here
(cherry-picked from `rewrite-6.6-smp`, by Ash Logan / linux-wiiu).

The config side (`CONFIG_SMP=y`, `CONFIG_NR_CPUS=3`) is set in
`board/wiiu/linux.config.fragment`.

## 0001-wiiu-Add-Espresso-SMP-erratum-to-atomic-ops.patch

The Espresso has a hardware bug in its atomic operations: a store-conditional
(`stwcx.`) can succeed when it shouldn't across cores, so without a workaround
shared data gets corrupted once more than one core runs. The patch inserts the
required cache flush (`dcbst`) before the store-conditional in every atomic
primitive (atomics, bitops, cmpxchg, futex, spinlocks), making locking correct
under SMP.

## 0002-wiiu-SMP-support.patch

The actual multi-core bring-up: start the secondary Espresso cores, wire up
inter-processor interrupts over the Latte IPC, and describe the extra CPUs in
the device tree. Without this only one core ever runs.

## Refreshing on a kernel bump

If you move the pinned SHA forward, re-cherry-pick these two commits onto the
new base and regenerate the patches; conflicts are most likely in the PPC
atomic headers.
