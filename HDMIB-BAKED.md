# HDMIB, baked into WhateverGreen

This tree is upstream WhateverGreen `093e76f` (2026-09-27) plus the Ice Lake HDMI-on-DDI-B module
written *into* the driver. Base: the module's `1.0-hj39` state.

What changed compared with the module's own release builds:

| | release builds (`build_weg_hdmib.sh`) | this tree |
|---|---|---|
| Where the code lives | `kern_igfx_hdmib.hpp` copied in by a script, `kern_igfx.cpp` edited with `perl -pi` | `WhateverGreen/kern_igfx_hdmib.hpp`, `kern_igfx.cpp` edited in the source, committed |
| Enable | boot-arg `-igfxhdmib` (nothing happens without it) | always active on the Ice Lake LP framebuffer; `igfxhdmib-off=1` disables |
| HDMI connector entry | `framebuffer-patch0-find/-replace` in `config.plist` | written into the platform table at kext load (`patchConnectorEntry`, entry walked by strided scan) |
| WhateverGreen's own DP→HDMI autopatch | silently disabled by the presence of `framebuffer-patch0` | disabled explicitly while the module owns the table |
| Kext name | `WhateverGreen-HDMIB.kext` | `WhateverGreen-baked.kext` (same bundle id, install it *as* `WhateverGreen.kext`) |

## Build

```bash
bash build_baked.sh            # Release  -> WhateverGreen-baked.kext
bash build_baked.sh --debug    # Debug
```

Needs full Xcode on an Intel or Apple Silicon Mac (the kext is always `x86_64`). The script only clones
Lilu and MacKernelSDK; it edits nothing.

## Install

1. `WhateverGreen-baked.kext` → `EFI/OC/Kexts/`, renamed to `WhateverGreen.kext` (replace the stock one;
   never keep both, the bundle id is the same).
2. `Kernel → Add` entry unchanged.
3. Remove `framebuffer-patch0-enable/-find/-replace` from the iGPU `DeviceProperties`. They are no longer
   needed; leaving them in is harmless (the module then steps aside and lets WhateverGreen apply them),
   but they are dead weight and will fail to match once the module has done its job in a future build.
4. `boot-args`: `-igfxhdmib` can be deleted. Everything else stays.

## Verify

```bash
ioreg -l | grep HDMIB
```

```
HDMIB-version = 1.0-hj39-baked
HDMIB-layout  = macOS 26 (Tahoe)
HDMIB-hooks   = installed
HDMIB-port    = ddi=1 gmbus=2 class=2 type=0x800 flags=0x2c1 OK (HDMI)
HDMIB-status  = hotplugs=1 edid-ok=1 ... vrr-off=1 port-fixups=0 ...
```

`HDMIB-port ... OK (HDMI)` means the baked connector entry landed. If it says `NOT HDMI`, look for the
`HDMIB: connector N on <id>: ...` line in `dmesg | grep HDMIB` — it names the entry that was
converted, or explains why none was (`platform id ... not resolved`, `no _gPlatformInformationList`).
The walk itself is visible: `HDMIB: platform id 0x... is not among the 22 entries` plus the list of ids it saw.

## Platform ids

The table is an array of 280-byte entries, one per platform id, and on Ice Lake it holds 22 of them (~6 KB, as
dumped in WhateverGreen's manual for 10.15/11). WhateverGreen's own lookup (`findFramebufferId`) scans a single page
(4 KB), which ends at entry 14: in that dump `0x8A5C0001` is entry 14 (offset 0xE38, inside the page) while
`0x8A5C0002` is entry 21 (offset 0x15E0, past it). That is why `0x8A5C0002` was reported as "not in the table"
while `0x8A5C0001` worked -- a scan window, not an id.

The module walks the array entry by entry instead, bounded by the kext image, so the id only has to exist:

| `AAPL,ig-platform-id` | result |
|---|---|
| `0x8A5C0002` (`02005C8A` as data), the retail MacBookAir9,1 path | entry 21 patched: `[3] busId 0x0A DP` -> `ddi 1 gmbus 2 pipe 2 HDMI` |
| `0x8A5C0001` (`01005C8A` as data) | entry 14 patched, same connector |
| not in the table at all | the driver works from an entry of its own, so the module takes the Ice Lake LP entry that has a DP connector on DDI D / GMBUS 10 (else the first one with a DP connector) and logs every id it walked |

If the chosen entry already carries a live connector on the target DDI (it does not on `0x8A5C0001`/`0x8A5C0002`,
both are `[0] LVDS, [2] bus 9, [3] bus 10`), the module converts *that* connector instead of creating a second one
on the same DDI, keeping the pipe/GMBUS pin the platform assigned. The log then reads
`ddi 1 is already used by connector N on 0x... (type=0x400): converting that one`.

## Boot arguments

All optional, all with baked defaults; none is required.

| Argument | Default | Meaning |
|---|---|---|
| `igfxhdmib-off=1` | 0 | disable the module (escape hatch) |
| `igfxhdmib-ddi=N` | 1 | DDI of the HDMI port; a free DP connector is rewritten to it (`busId` = N+1, `pipe`/`pad` = 2/0); if the table already has a connector on that DDI, that one is converted and keeps its pipe/busId |
| `igfxhdmib-fb=N` | 2 (auto) | framebuffer index of that port |
| `igfxhdmib-bootdetect=S` | 3 | run the hotplug S seconds after the first mode set (0 = off) |
| `igfxhdmib-wake=1` | 0 | opt-in wake fallback for "online after wake but dark" |
| `igfxhdmib-wake-delay=M` | 1500 | delay before that fallback fires |
| `igfxhdmib-hwcursor=0\|1` | 1 | hardware cursor on the HDMI framebuffer |
| `igfxhdmib-swcursor=1` | 0 | software cursor on every framebuffer |
| `igfxhdmib-aux=0` | 1 | do not short-circuit the accelerator's AUX reads |
| `igfxhdmib-dc6fix=0` | 1 | do not skip the second `enableHWDC6()` |
| `igfxhdmib-edid-fallback=1` | 0 | present a generic 1024×768@60 EDID when the sink does not answer |
| `igfxhdmib-rgb=-1\|0\|1\|2` | -1 | colour-format handling (`-1` = automatic) |
| `igfxhdmib-force=1` | 0 | run on an unverified macOS version — at your own risk |

## Reverting

`git checkout` the parent commit, or delete `WhateverGreen/kern_igfx_hdmib.hpp` and the three edits in
`kern_igfx.cpp` (`#include`, the `hdmiAutopatch` guard in `processKernel`, the `HDMIB::install` call in
`processKext`). The parent commit is plain upstream `093e76f`.

## Caveats

- Ice Lake **H** (`AppleIntelICLHPGraphicsFramebuffer`) is out of scope: the module returns early there.
  Because `HDMIB::enabled()` also gates WhateverGreen's DP→HDMI autopatch for `CpuGeneration::IceLake`,
  an Ice Lake H machine running this kext loses that autopatch. Use `igfxhdmib-off=1` there.
- Nothing in this tree has been built or run by whoever baked it in (no macOS toolchain); see `REVIEW.md`
  in the delivery folder for what was and was not verified.
