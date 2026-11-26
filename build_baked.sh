#!/bin/bash
# Builds this WhateverGreen tree (WhateverGreen + the baked HDMIB module) into WhateverGreen.kext.
#
#   bash build_baked.sh            # Release
#   bash build_baked.sh --debug    # Debug
#
# Unlike build_weg_hdmib.sh in the module repository this script edits nothing: the module already lives in
# WhateverGreen/kern_igfx_hdmib.hpp and kern_igfx.cpp already includes and calls it. It only clones the two
# build dependencies (Lilu, MacKernelSDK) and runs xcodebuild.
#
# Needs full Xcode (not only the Command Line Tools) on an Intel or Apple Silicon Mac; the kext is always x86_64.
set -e
CONF=Release; [ "$1" = "--debug" ] && CONF=Debug
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/build_baked"

[ -f "$HERE/WhateverGreen/kern_igfx_hdmib.hpp" ] || { echo "run me from the WhateverGreen source root"; exit 1; }
[ "$(grep -c 'HDMIB::install' "$HERE/WhateverGreen/kern_igfx.cpp")" = "1" ] || { echo "ERROR: kern_igfx.cpp does not call HDMIB::install"; exit 1; }

xcodebuild -version >/dev/null 2>&1 || { echo "Full Xcode is required. Try: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; exit 1; }

mkdir -p "$W"
clone() { [ -d "$W/$1/.git" ] || git clone -q https://github.com/acidanthera/$1.git "$W/$1"; [ -n "$2" ] && git -C "$W/$1" checkout -q "$2"; true; }
clone Lilu "$LILU_REF"
clone MacKernelSDK "$MKS_REF"
echo "Lilu $(git -C "$W/Lilu" rev-parse --short HEAD)  MacKernelSDK $(git -C "$W/MacKernelSDK" rev-parse --short HEAD)"

# 1) Lilu (Debug: the framebuffer patches log through it) and its SDK
cp -R "$W/MacKernelSDK" "$W/Lilu/MacKernelSDK"
( cd "$W/Lilu" && xcodebuild -project Lilu.xcodeproj -scheme Lilu -configuration Debug -sdk macosx \
    ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build \
    SYMROOT="$W/lilu_out" >/dev/null )

# 2) WhateverGreen, with Lilu.kext + MacKernelSDK in place
rm -rf "$HERE/Lilu.kext" "$HERE/MacKernelSDK"
cp -R "$W/lilu_out/Debug/Lilu.kext" "$HERE/Lilu.kext"
cp -R "$W/MacKernelSDK" "$HERE/MacKernelSDK"
( cd "$HERE" && xcodebuild -project WhateverGreen.xcodeproj -scheme WhateverGreen -configuration $CONF -sdk macosx \
    ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build \
    SYMROOT="$W/weg_out" )

rm -rf "$HERE/WhateverGreen-baked.kext"
cp -R "$W/weg_out/$CONF/WhateverGreen.kext" "$HERE/WhateverGreen-baked.kext"
echo
echo "DONE: $HERE/WhateverGreen-baked.kext"
echo "  version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$HERE/WhateverGreen-baked.kext/Contents/Info.plist" 2>/dev/null)"
echo "  sha1:    $(shasum -a 1 "$HERE/WhateverGreen-baked.kext/Contents/MacOS/WhateverGreen" | cut -d' ' -f1)"
echo
echo "Install it AS WhateverGreen.kext in EFI/OC/Kexts (it replaces the stock kext, same bundle id), then:"
echo "  * no boot-arg is required, no DeviceProperties patch is required;"
echo "  * ioreg -l | grep HDMIB    ->  HDMIB-version = 1.0-hj39-baked, HDMIB-port = ... OK (HDMI);"
echo "  * igfxhdmib-off=1 keeps the escape hatch if the machine misbehaves."
