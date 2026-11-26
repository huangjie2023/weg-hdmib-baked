# HDMIB, baked into WhateverGreen

This tree is upstream WhateverGreen `093e76f` (2026-09-27) plus the Ice Lake HDMI-on-DDI-B module
written *into* the driver. Base: the module's `1.0-hj39` state.

What changed compared with the module's own release builds:

| | release builds (`build_weg_hdmib.sh`) | this tree |
|---|---|---|
| Where the code lives | `kern_igfx_hdmib.hpp` copied in by a script, `kern_igfx.cpp` edited with `perl -pi` | `WhateverGreen/kern_igfx_hdmib.hpp`, `kern_igfx.cpp` edited in the source, committed |
| Enable | boot-arg `-igfxhdmib` (nothing happens without it) | always active on the Ice Lake LP framebuffer; `igfxhdmib-off=1` disables |
| HDMI connector entry | `framebuffer-patch0-find/-replace` in `config.plist` | written into the platform table at kext load (`patchConnectorEntry`) |
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
`HDMIB: connector N on 0x01005C8A: ...` line in `dmesg | grep HDMIB` — it names the entry that was
converted, or explains why none was (`platform id ... not in the table`, `no _gPlatformInformationList`).

## Boot arguments

All optional, all with baked defaults; none is required.

| Argument | Default | Meaning |
|---|---|---|
| `igfxhdmib-off=1` | 0 | disable the module (escape hatch) |
| `igfxhdmib-ddi=N` | 1 | DDI of the HDMI port; the baked connector entry follows it (`busId` = N+1, `pipe`/`pad` stay at the verified 2/0) |
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
