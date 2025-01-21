#!/bin/bash

set -ex

function finalize_locally() {
    local top="../../"
    source $top/build/make/tools/finalization/environment.sh

    # default target to modify tree and build SDK
    local m="$top/build/soong/soong_ui.bash --make-mode TARGET_PRODUCT=aosp_arm64 TARGET_RELEASE=ap4a TARGET_BUILD_VARIANT=userdebug DIST_DIR=out/dist"

    # adb keys
    # The keys are already generated for Android 15. Keeping the command (commented out) for future reference.
    # $m adb
    # LOGNAME=android-eng HOSTNAME=google.com "$top/out/host/linux-x86/bin/adb" keygen "$top/vendor/google/security/adb/${FINAL_PLATFORM_VERSION}.adb_key"

    # Build Platform SDKs.
    # $top/build/soong/soong_ui.bash --make-mode TARGET_PRODUCT=sdk TARGET_RELEASE=ap2a TARGET_BUILD_VARIANT=user sdk dist sdk_repo DIST_DIR=out/dist

    # Build Modules SDKs.
    TARGET_RELEASE=ap4a TARGET_BUILD_VARIANT=userdebug UNBUNDLED_BUILD_SDKS_FROM_SOURCE=true DIST_DIR=out/dist "$top/packages/modules/common/build/mainline_modules_sdks.sh" --build-release=VanillaIceCream

    # Update prebuilts.
    "$top/prebuilts/build-tools/path/linux-x86/python3" -W ignore::DeprecationWarning "$top/prebuilts/sdk/update_prebuilts.py" --local_mode -f ${FINAL_PLATFORM_SDK_VERSION} -e ${FINAL_MAINLINE_EXTENSION} --bug 1 1
}

finalize_locally
