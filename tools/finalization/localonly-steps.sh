#!/bin/bash

set -ex

module_build_release_ver=latest

function finalize_locally() {
    if [ ! -d build/make ]; then
        local top="../../../../"
    else
        local top="./"
    fi

    source $top/build/make/tools/finalization/environment.sh

    # default target to modify tree and build SDK
    local m="$top/build/soong/soong_ui.bash --make-mode TARGET_PRODUCT=aosp_arm64 TARGET_RELEASE=ap4a TARGET_BUILD_VARIANT=userdebug DIST_DIR=out/dist"

    # adb keys
    # The keys are already generated for Android 15. Keeping the command (commented out) for future reference.
    # $m adb
    # LOGNAME=android-eng HOSTNAME=google.com "$top/out/host/linux-x86/bin/adb" keygen "$top/vendor/google/security/adb/${FINAL_PLATFORM_VERSION}.adb_key"

    # Build Modules SDKs.
    echo "Building Modules SDKs..."
    TARGET_RELEASE=ap4a TARGET_BUILD_VARIANT=userdebug UNBUNDLED_BUILD_SDKS_FROM_SOURCE=true DIST_DIR=out/dist "$top/packages/modules/common/build/mainline_modules_sdks.sh" --build-release=$module_build_release_ver

    # Update prebuilts.
    echo "Updating module SDK prebuilts..."
    "$top/prebuilts/build-tools/path/linux-x86/python3" -W ignore::DeprecationWarning "$top/prebuilts/sdk/update_prebuilts.py" --local_mode -f ${FINAL_PLATFORM_SDK_VERSION} -e ${FINAL_MAINLINE_EXTENSION} --bug 1 1 || {
        echo "Platform SDK update failed, but continuing..."
    }
}

function copy_sdk_files() {
    if [ ! -d build/make ]; then
        local top="../../../../"
    else
        local top="./"
    fi

    local dist_dir=$top/out/dist
    local sdk_dist_dir=$dist_dir/mainline-sdks/for-$module_build_release_ver-build/current
    local module_sdk_dir=$top/prebuilts/module_sdk

    for rawString in `cat $top/build/make/tools/finalization/sdk-files.txt`; do
        packageName=${rawString%\|*}
        fileName=${rawString#*\|}
        several_dir=false
        if [[ -d $sdk_dist_dir/$packageName/host-exports ]]; then
            rm -Rf $module_sdk_dir/$fileName/current/host-exports/*
            mkdir -p $module_sdk_dir/$fileName/current/host-exports
            unzip $sdk_dist_dir/$packageName/host-exports/${packageName##*.}*.zip -d $module_sdk_dir/$fileName/current/host-exports/
            several_dir=true
        fi
        if [[ -d $sdk_dist_dir/$packageName/test-exports ]]; then
            rm -Rf $module_sdk_dir/$fileName/current/test-exports/*
            mkdir -p $module_sdk_dir/$fileName/current/test-exports
            unzip $sdk_dist_dir/$packageName/test-exports/${packageName##*.}*.zip -d $module_sdk_dir/$fileName/current/test-exports/
            several_dir=true
        fi
        if [[ $several_dir = true ]]; then
            rm -Rf $module_sdk_dir/$fileName/current/sdk/*
            mkdir -p $module_sdk_dir/$fileName/current/sdk
            unzip $sdk_dist_dir/$packageName/sdk/${packageName##*.}*.zip -d $module_sdk_dir/$fileName/current/sdk/
        else
            rm -Rf $module_sdk_dir/$fileName/current/*
            mkdir -p $module_sdk_dir/$fileName/current
            unzip $sdk_dist_dir/$packageName/sdk/${packageName##*.}*.zip -d $module_sdk_dir/$fileName/current/
        fi
    done
}

finalize_locally
copy_sdk_files

unset module_build_release_ver
