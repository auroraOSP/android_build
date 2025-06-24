# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# gettop is duplicated here and in shell_utils.mk, because it's difficult
# to find shell_utils.make without it for all the novel ways this file can be
# sourced.  Other common functions should only be in one place or the other.
function _gettop_once
{
    local TOPFILE=build/make/core/envsetup.mk
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ] ; then
        # The following circumlocution ensures we remove symlinks from TOP.
        (cd "$TOP"; PWD= /bin/pwd)
    else
        if [ -f $TOPFILE ] ; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            local HERE=$PWD
            local T=
            while [ \( ! \( -f $TOPFILE \) \) -a \( "$PWD" != "/" \) ]; do
                \cd ..
                T=`PWD= /bin/pwd -P`
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}
T=$(_gettop_once)
if [ ! "$T" ]; then
    echo "Couldn't locate the top of the tree. Always source build/envsetup.sh from the root of the tree." >&2
    return 1
fi
IMPORTING_ENVSETUP=true source $T/build/make/shell_utils.sh

# Get all the build variables needed by this script in a single call to the build system.
function build_build_var_cache()
{
    local T=$(gettop)
    # Grep out the variable names from the script.
    cached_vars=(`cat $T/build/envsetup.sh $T/vendor/aurora/build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/_get_build_var_cached/) print $(i+1)}' | sort -u | tr '\n' ' '`)
    cached_abs_vars=(`cat $T/build/envsetup.sh $T/vendor/aurora/build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/_get_abs_build_var_cached/) print $(i+1)}' | sort -u | tr '\n' ' '`)
    # Call the build system to dump the "<val>=<value>" pairs as a shell script.
    build_dicts_script=`\builtin cd $T; build/soong/soong_ui.bash --dumpvars-mode \
                        --vars="${cached_vars[*]}" \
                        --abs-vars="${cached_abs_vars[*]}" \
                        --var-prefix=var_cache_ \
                        --abs-var-prefix=abs_var_cache_`
    local ret=$?
    if [ $ret -ne 0 ]
    then
        unset build_dicts_script
        return $ret
    fi
    # Execute the script to store the "<val>=<value>" pairs as shell variables.
    eval "$build_dicts_script"
    ret=$?
    unset build_dicts_script
    if [ $ret -ne 0 ]
    then
        return $ret
    fi
    BUILD_VAR_CACHE_READY="true"
}

# Delete the build var cache, so that we can still call into the build system
# to get build variables not listed in this script.
function destroy_build_var_cache()
{
    unset BUILD_VAR_CACHE_READY
    local v
    for v in $cached_vars; do
      unset var_cache_$v
    done
    unset cached_vars
    for v in $cached_abs_vars; do
      unset abs_var_cache_$v
    done
    unset cached_abs_vars
}

# Get the value of a build variable as an absolute path.
function _get_abs_build_var_cached()
{
    if [ "$BUILD_VAR_CACHE_READY" = "true" ]
    then
        eval "echo \"\${abs_var_cache_$1}\""
        return
    fi

    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    (\cd $T; build/soong/soong_ui.bash --dumpvar-mode --abs $1)
}

# Get the exact value of a build variable.
function _get_build_var_cached()
{
    if [ "$BUILD_VAR_CACHE_READY" = "true" ]
    then
        eval "echo \"\${var_cache_$1}\""
        return 0
    fi

    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return 1
    fi
    (\cd $T; build/soong/soong_ui.bash --dumpvar-mode $1)
}

# This logic matches envsetup.mk
function get_host_prebuilt_prefix
{
  local un=$(uname)
  if [[ $un == "Linux" ]] ; then
    echo linux-x86
  elif [[ $un == "Darwin" ]] ; then
    echo darwin-x86
  else
    echo "Error: Invalid host operating system: $un" 1>&2
  fi
}

# Add directories to PATH that are dependent on the lunch target.
# For directories that are not lunch-specific, add them in set_global_paths
function set_lunch_paths()
{
    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return
    fi

    ##################################################################
    #                                                                #
    #              Read me before you modify this code               #
    #                                                                #
    #   This function sets ANDROID_LUNCH_BUILD_PATHS to what it is   #
    #   adding to PATH, and the next time it is run, it removes that #
    #   from PATH.  This is required so lunch can be run more than   #
    #   once and still have working paths.                           #
    #                                                                #
    ##################################################################

    # Note: on windows/cygwin, ANDROID_LUNCH_BUILD_PATHS will contain spaces
    # due to "C:\Program Files" being in the path.

    # Handle compat with the old ANDROID_BUILD_PATHS variable.
    # TODO: Remove this after we think everyone has lunched again.
    if [ -z "$ANDROID_LUNCH_BUILD_PATHS" -a -n "$ANDROID_BUILD_PATHS" ] ; then
      ANDROID_LUNCH_BUILD_PATHS="$ANDROID_BUILD_PATHS"
      ANDROID_BUILD_PATHS=
    fi
    if [ -n "$ANDROID_PRE_BUILD_PATHS" ] ; then
        export PATH=${PATH/$ANDROID_PRE_BUILD_PATHS/}
        # strip leading ':', if any
        export PATH=${PATH/:%/}
        ANDROID_PRE_BUILD_PATHS=
    fi

    # Out with the old...
    if [ -n "$ANDROID_LUNCH_BUILD_PATHS" ] ; then
        export PATH=${PATH/$ANDROID_LUNCH_BUILD_PATHS/}
    fi

    # And in with the new...
    local SOONG_HOST_OUT_EXECUTABLES=$(_get_abs_build_var_cached SOONG_HOST_OUT_EXECUTABLES)
    local HOST_OUT_EXECUTABLES=$(_get_abs_build_var_cached HOST_OUT_EXECUTABLES)
    # Binaries in build/soong/bin should always be preferred over any build path.
    ANDROID_LUNCH_BUILD_PATHS=$T/build/soong/bin:${SOONG_HOST_OUT_EXECUTABLES}
    if [ "${HOST_OUT_EXECUTABLES}" != "${SOONG_HOST_OUT_EXECUTABLES}" ]; then
        ANDROID_LUNCH_BUILD_PATHS+=:${HOST_OUT_EXECUTABLES}
    fi

    # Append llvm binutils prebuilts path to ANDROID_LUNCH_BUILD_PATHS.
    local ANDROID_LLVM_BINUTILS=$(_get_abs_build_var_cached ANDROID_CLANG_PREBUILTS)/llvm-binutils-stable
    ANDROID_LUNCH_BUILD_PATHS+=:$ANDROID_LLVM_BINUTILS

    # Set up ASAN_SYMBOLIZER_PATH for SANITIZE_HOST=address builds.
    export ASAN_SYMBOLIZER_PATH=$ANDROID_LLVM_BINUTILS/llvm-symbolizer

    # Append asuite prebuilts path to ANDROID_LUNCH_BUILD_PATHS.
    local os_arch=$(_get_build_var_cached HOST_PREBUILT_TAG)
    ANDROID_LUNCH_BUILD_PATHS+=:$T/prebuilts/asuite/acloud/$os_arch
    ANDROID_LUNCH_BUILD_PATHS+=:$T/prebuilts/asuite/aidegen/$os_arch
    ANDROID_LUNCH_BUILD_PATHS+=:$T/prebuilts/asuite/atest/$os_arch

    export ANDROID_JAVA_HOME=$(_get_abs_build_var_cached ANDROID_JAVA_HOME)
    export JAVA_HOME=$ANDROID_JAVA_HOME
    export ANDROID_JAVA_TOOLCHAIN=$(_get_abs_build_var_cached ANDROID_JAVA_TOOLCHAIN)
    ANDROID_LUNCH_BUILD_PATHS+=:$ANDROID_JAVA_TOOLCHAIN

    # Fix up PYTHONPATH
    if [ -n $ANDROID_PYTHONPATH ]; then
        export PYTHONPATH=${PYTHONPATH//$ANDROID_PYTHONPATH/}
    fi
    # //development/python-packages contains both a pseudo-PYTHONPATH which
    # mimics an already assembled venv, but also contains real Python packages
    # that are not in that layout until they are installed. We can fake it for
    # the latter type by adding the package source directories to the PYTHONPATH
    # directly. For the former group, we only need to add the python-packages
    # directory itself.
    #
    # This could be cleaned up by converting the remaining packages that are in
    # the first category into a typical python source layout (that is, another
    # layer of directory nesting) and automatically adding all subdirectories of
    # python-packages to the PYTHONPATH instead of manually curating this. We
    # can't convert the packages like adb to the other style because doing so
    # would prevent exporting type info from those packages.
    #
    # http://b/266688086
    export ANDROID_PYTHONPATH=$T/development/python-packages/adb:$T/development/python-packages/gdbrunner:$T/development/python-packages:
    if [ -n $VENDOR_PYTHONPATH ]; then
        ANDROID_PYTHONPATH=$ANDROID_PYTHONPATH$VENDOR_PYTHONPATH
    fi
    export PYTHONPATH=$ANDROID_PYTHONPATH$PYTHONPATH

    unset ANDROID_PRODUCT_OUT
    export ANDROID_PRODUCT_OUT=$(_get_abs_build_var_cached PRODUCT_OUT)
    export OUT=$ANDROID_PRODUCT_OUT

    unset ANDROID_HOST_OUT
    export ANDROID_HOST_OUT=$(_get_abs_build_var_cached HOST_OUT)

    unset ANDROID_SOONG_HOST_OUT
    export ANDROID_SOONG_HOST_OUT=$(_get_abs_build_var_cached SOONG_HOST_OUT)

    unset ANDROID_HOST_OUT_TESTCASES
    export ANDROID_HOST_OUT_TESTCASES=$(_get_abs_build_var_cached HOST_OUT_TESTCASES)

    unset ANDROID_TARGET_OUT_TESTCASES
    export ANDROID_TARGET_OUT_TESTCASES=$(_get_abs_build_var_cached TARGET_OUT_TESTCASES)

    # Finally, set PATH
    export PATH=$ANDROID_LUNCH_BUILD_PATHS:$PATH
}

# Add directories to PATH that are NOT dependent on the lunch target.
# For directories that are lunch-specific, add them in set_lunch_paths
function set_global_paths()
{
    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return
    fi

    ##################################################################
    #                                                                #
    #              Read me before you modify this code               #
    #                                                                #
    #   This function sets ANDROID_GLOBAL_BUILD_PATHS to what it is  #
    #   adding to PATH, and the next time it is run, it removes that #
    #   from PATH.  This is required so envsetup.sh can be sourced   #
    #   more than once and still have working paths.                 #
    #                                                                #
    ##################################################################

    # Out with the old...
    if [ -n "$ANDROID_GLOBAL_BUILD_PATHS" ] ; then
        export PATH=${PATH/$ANDROID_GLOBAL_BUILD_PATHS:/}
    fi

    # And in with the new...
    ANDROID_GLOBAL_BUILD_PATHS=$T/build/soong/bin
    ANDROID_GLOBAL_BUILD_PATHS+=:$T/build/bazel/bin
    ANDROID_GLOBAL_BUILD_PATHS+=:$T/development/scripts
    ANDROID_GLOBAL_BUILD_PATHS+=:$T/prebuilts/devtools/tools

    # add kernel specific binaries
    if [ $(uname -s) = Linux ] ; then
        ANDROID_GLOBAL_BUILD_PATHS+=:$T/prebuilts/misc/linux-x86/dtc
        ANDROID_GLOBAL_BUILD_PATHS+=:$T/prebuilts/misc/linux-x86/libufdt
    fi

    # If prebuilts/android-emulator/<system>/ exists, prepend it to our PATH
    # to ensure that the corresponding 'emulator' binaries are used.
    case $(uname -s) in
        Darwin)
            ANDROID_EMULATOR_PREBUILTS=$T/prebuilts/android-emulator/darwin-x86_64
            ;;
        Linux)
            ANDROID_EMULATOR_PREBUILTS=$T/prebuilts/android-emulator/linux-x86_64
            ;;
        *)
            ANDROID_EMULATOR_PREBUILTS=
            ;;
    esac
    if [ -n "$ANDROID_EMULATOR_PREBUILTS" -a -d "$ANDROID_EMULATOR_PREBUILTS" ]; then
        ANDROID_GLOBAL_BUILD_PATHS+=:$ANDROID_EMULATOR_PREBUILTS
        export ANDROID_EMULATOR_PREBUILTS
    fi

    # Finally, set PATH
    export PATH=$ANDROID_GLOBAL_BUILD_PATHS:$PATH
}

function printconfig()
{
    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    _get_build_var_cached report_config
}

function set_stuff_for_environment()
{
    set_lunch_paths
    set_sequence_number
}

function set_sequence_number()
{
    export BUILD_ENV_SEQUENCE_NUMBER=13
}

# Takes a command name, and check if it's in ENVSETUP_NO_COMPLETION or not.
function should_add_completion() {
    local cmd="$(basename $1| sed 's/_completion//' |sed 's/\.\(.*\)*sh$//')"
    case :"$ENVSETUP_NO_COMPLETION": in
        *:"$cmd":*)
            return 1
            ;;
    esac
    return 0
}

function addcompletions()
{
    local f=

    # Keep us from trying to run in something that's neither bash nor zsh.
    if [ -z "$BASH_VERSION" -a -z "$ZSH_VERSION" ]; then
        return
    fi

    # Keep us from trying to run in bash that's too old.
    if [ -n "$BASH_VERSION" -a ${BASH_VERSINFO[0]} -lt 3 ]; then
        return
    fi

    local completion_files=(
      packages/modules/adb/adb.bash
      system/core/fastboot/fastboot.bash
      tools/asuite/asuite.sh
    )
    # Completion can be disabled selectively to allow users to use non-standard completion.
    # e.g.
    # ENVSETUP_NO_COMPLETION=adb # -> disable adb completion
    # ENVSETUP_NO_COMPLETION=adb:bit # -> disable adb and bit completion
    local T=$(gettop)
    for f in ${completion_files[*]}; do
        f="$T/$f"
        if [ ! -f "$f" ]; then
          echo "Warning: completion file $f not found"
        elif should_add_completion "$f"; then
            . $f
        fi
    done

    if [ -z "$ZSH_VERSION" ]; then
        # Doesn't work in zsh.
        complete -o nospace -F _croot croot
        # TODO(b/244559459): Support b autocompletion for zsh
        complete -F _bazel__complete -o nospace b
    fi
    complete -F _lunch lunch
    complete -F _lunch_completion lunch2

    complete -F _complete_android_module_names pathmod
    complete -F _complete_android_module_names gomod
    complete -F _complete_android_module_names outmod
    complete -F _complete_android_module_names installmod
    complete -F _complete_android_module_names m
}

function add_lunch_combo()
{
    if [ -n "$ZSH_VERSION" ]; then
        echo -n "${funcfiletrace[1]}: "
    else
        echo -n "${BASH_SOURCE[1]}:${BASH_LINENO[0]}: "
    fi
    echo "add_lunch_combo is obsolete. Use COMMON_LUNCH_CHOICES in your AndroidProducts.mk instead."
}

function print_lunch_menu()
{
    local uname=$(uname)
    local choices
    choices=$(TARGET_BUILD_APPS= TARGET_PRODUCT= TARGET_RELEASE= TARGET_BUILD_VARIANT= _get_build_var_cached COMMON_LUNCH_CHOICES 2>/dev/null)
    local ret=$?

    echo
    echo "You're building on" $uname
    echo

    if [ $ret -ne 0 ]
    then
        echo "Warning: Cannot display lunch menu."
        echo
        echo "Note: You can invoke lunch with an explicit target:"
        echo
        echo "  usage: lunch [target]" >&2
        echo
        return
    fi

    echo "Lunch menu .. Here are the common combinations:"

    local i=1
    local choice
    for choice in $(echo $choices)
    do
        echo "     $i. $choice"
        i=$(($i+1))
    done

    echo
}

function _lunch_meat()
{
    local product=$1
    local release=$2
    local variant=$3

    TARGET_PRODUCT=$product \
    TARGET_RELEASE=$release \
    TARGET_BUILD_VARIANT=$variant \
    TARGET_BUILD_APPS= \
    build_build_var_cache
    if [ $? -ne 0 ]
    then
        if [[ "$product" =~ .*_(eng|user|userdebug) ]]
        then
            echo "Did you mean -${product/*_/}? (dash instead of underscore)"
        fi
        echo
        echo "** Don't have a product spec for: '$product'"
        echo "** Do you have the right repo manifest?"
        product=
    fi

    if [ -z "$product" -o -z "$variant" ]
    then
        echo
        return 1
    fi
    export TARGET_PRODUCT=$(_get_build_var_cached TARGET_PRODUCT)
    export TARGET_BUILD_VARIANT=$(_get_build_var_cached TARGET_BUILD_VARIANT)
    export TARGET_RELEASE=$release
    # Note this is the string "release", not the value of the variable.
    export TARGET_BUILD_TYPE=release
    # Undo any previous tapas or banchan setup
    export TARGET_BUILD_APPS=

    local no_kernel=$(_get_build_var_cached TARGET_NO_KERNEL)
    local prebuilt_kernel=$(_get_build_var_cached TARGET_PREBUILT_KERNEL)
    if [[ "$no_kernel" == "true" ]] || [ -n "$prebuilt_kernel" ]; then
        unset INLINE_KERNEL_BUILDING
        if [ -n "$(_get_build_var_cached TARGET_KERNEL_PLATFORM_SOURCE)" ]; then
            build_kernel
        fi
    else
        export INLINE_KERNEL_BUILDING=true
    fi

    [[ -n "${ANDROID_QUIET_BUILD:-}" ]] || echo

    fixup_common_out_dir

    set_stuff_for_environment
    [[ -n "${ANDROID_QUIET_BUILD:-}" ]] || printconfig

    if [[ -z "${ANDROID_QUIET_BUILD}" && -z "${AURORA_BUILD}" ]]; then
        local spam_for_lunch=$(gettop)/build/make/tools/envsetup/spam_for_lunch
        if [[ -x $spam_for_lunch ]]; then
            $spam_for_lunch
        fi
    fi

    destroy_build_var_cache

    if [[ -n "${CHECK_MU_CONFIG:-}" ]]; then
      check_mu_config
    fi
}

unset COMMON_LUNCH_CHOICES_CACHE
# Tab completion for lunch.
function _lunch()
{
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [ -z "$COMMON_LUNCH_CHOICES_CACHE" ]; then
        COMMON_LUNCH_CHOICES_CACHE=$(TARGET_BUILD_APPS= _get_build_var_cached COMMON_LUNCH_CHOICES)
    fi

    COMPREPLY=( $(compgen -W "${COMMON_LUNCH_CHOICES_CACHE}" -- ${cur}) )
    return 0
}

function _lunch_usage()
{
    (
        echo "The lunch command selects the configuration to use for subsequent"
        echo "Android builds."
        echo
        echo "Usage: lunch TARGET_PRODUCT [TARGET_RELEASE [TARGET_BUILD_VARIANT]]"
        echo
        echo "  Choose the product, release and variant to use. If not"
        echo "  supplied, TARGET_RELEASE will be 'trunk_staging' and"
        echo "  TARGET_BUILD_VARIANT will be 'eng'"
        echo
        echo
        echo "Usage: lunch TARGET_PRODUCT-TARGET_RELEASE-TARGET_BUILD_VARIANT"
        echo
        echo "  Chose the product, release and variant to use. This"
        echo "  legacy format is maintained for compatibility."
        echo
        echo
        echo "Note that the previous interactive menu and list of hard-coded"
        echo "list of curated targets has been removed. If you would like the"
        echo "list of products, release configs for a particular product, or"
        echo "variants, run the following as individual commands:"
        echo "list_products, list_releases, or list_variants"
        echo "respectively."
        echo
    ) 1>&2
}

function _lunch_store_leftovers()
{
    local product=$1
    local release=$2
    local variant=$3

    local dot_leftovers="$(getoutdir)/.leftovers"
    rm -f $dot_leftovers
    echo "$product $release $variant" > $dot_leftovers
}

function lunch()
{
    if [[ $# -eq 1 && $1 = "--help" ]]; then
        _lunch_usage
        return 0
    fi
    if [[ $# -eq 0 ]]; then
        echo "No target specified. See lunch --help" 1>&2
        return 1
    fi
    if [[ $# -gt 3 ]]; then
        echo "Too many parameters given. See lunch --help" 1>&2
        return 1
    fi

    local product release variant

    # Handle the legacy format
    local legacy=$(echo $1 | grep "-")
    if [[ $# -eq 1 && -n $legacy ]]; then
        IFS="-" read -r product release variant <<< "$1"
        if [[ -z "$product" ]] || [[ -z "$release" ]] || [[ -z "$variant" ]]; then
            echo "Invalid lunch combo: $1" 1>&2
            echo "Valid combos must be of the form <product>-<release>-<variant> when using" 1>&2
            echo "the legacy format.  Run 'lunch --help' for usage." 1>&2
            return 1
        fi
    fi

    # Handle the new format.
    if [[ -z $legacy ]]; then
        product=$1
        release=$2
        if [[ -z $release ]]; then
            release=trunk_staging
        fi
        variant=$3
        if [[ -z $variant ]]; then
            variant=eng
        fi
    fi

    if ! check_product $product $release
    then
        # if we can't find a product, try to grab it off the auroraOS GitHub
        T=$(gettop)
        cd $T > /dev/null
        vendor/aurora/build/tools/roomservice.py $product
        cd - > /dev/null
        check_product $product $release
    else
        T=$(gettop)
        cd $T > /dev/null
        vendor/aurora/build/tools/roomservice.py $product true
        cd - > /dev/null
    fi

    # Validate the selection and set all the environment stuff
    _lunch_meat $product $release $variant

    _lunch_store_leftovers $product $release $variant
}

function leftovers()
{
    if [ -t 1 ] && [ $(tput colors) -ge 8 ]; then
        local style_reset="$(tput sgr0)"
        local style_red="$(tput setaf 1)"
        local style_green="$(tput setaf 2)"
        local style_bold="$(tput bold)"
    fi
    local FAIL="${style_bold}${style_red}ERROR${style_reset}"
    local INFO="${style_bold}${style_green}INFO${style_reset}"

    if [[ $# -eq 1 && ($1 = "--help" || $1 == "-h" || $1 == "help") ]]; then
        (
            echo "The leftovers command restores your previous lunch choices, if found."
            echo
            echo "Set ${style_bold}USE_LEFTOVERS=1${style_reset} in your environment to automatically run this"
            echo "from ${style_bold}build/envsetup.sh${style_reset}."
        ) 1>&2
        return
    fi

    local dot_leftovers="$(getoutdir)/.leftovers"

    # seamlessly migrate old .leftovers location
    local old_leftovers="$(gettop)/.leftovers"
    if [[ -e $old_leftovers ]]
    then
        if [[ -e $dot_leftovers ]]; then
            rm $old_leftovers
        else
            mv $old_leftovers $dot_leftovers
        fi
    fi

    if [ ! -f $dot_leftovers ]; then
        echo -e "$FAIL: .leftovers not found. Run ${style_bold}lunch${style_reset} first."
        return 1
    fi

    local product release variant
    IFS=" " read -r product release variant < "$dot_leftovers"

    echo "$INFO: Loading previous lunch: ${style_bold}$product $release $variant${style_reset}"
    lunch $product $release $variant
}

unset ANDROID_LUNCH_COMPLETION_PRODUCT_CACHE
unset ANDROID_LUNCH_COMPLETION_CHOSEN_PRODUCT
unset ANDROID_LUNCH_COMPLETION_RELEASE_CACHE
# Tab completion for lunch.
function _lunch_completion()
{
    # Available products
    if [[ $COMP_CWORD -eq 1 ]] ; then
        if [[ -z $ANDROID_LUNCH_COMPLETION_PRODUCT_CACHE ]]; then
            ANDROID_LUNCH_COMPLETION_PRODUCT_CACHE=$(list_products)
        fi
        COMPREPLY=( $(compgen -W "${ANDROID_LUNCH_COMPLETION_PRODUCT_CACHE}" -- "${COMP_WORDS[COMP_CWORD]}") )
    fi

    # Available release configs
    if [[ $COMP_CWORD -eq 2 ]] ; then
        if [[ -z $ANDROID_LUNCH_COMPLETION_RELEASE_CACHE || $ANDROID_LUNCH_COMPLETION_CHOSEN_PRODUCT != ${COMP_WORDS[1]} ]] ; then
            ANDROID_LUNCH_COMPLETION_RELEASE_CACHE=$(list_releases ${COMP_WORDS[1]})
            ANDROID_LUNCH_COMPLETION_CHOSEN_PRODUCT=${COMP_WORDS[1]}
        fi
        COMPREPLY=( $(compgen -W "${ANDROID_LUNCH_COMPLETION_RELEASE_CACHE}" -- "${COMP_WORDS[COMP_CWORD]}") )
    fi

    # Available variants
    if [[ $COMP_CWORD -eq 3 ]] ; then
        COMPREPLY=(user userdebug eng)
    fi

    return 0
}


# Configures the build to build unbundled apps.
# Run tapas with one or more app names (from LOCAL_PACKAGE_NAME)
function tapas()
{
    local showHelp="$(echo $* | xargs -n 1 echo | \grep -E '^(help)$' | xargs)"
    local arch="$(echo $* | xargs -n 1 echo | \grep -E '^(arm|x86|arm64|x86_64)$' | xargs)"
    # TODO(b/307975293): Expand tapas to take release arguments (and update hmm() usage).
    local release="trunk_staging"
    local variant="$(echo $* | xargs -n 1 echo | \grep -E '^(user|userdebug|eng)$' | xargs)"
    local density="$(echo $* | xargs -n 1 echo | \grep -E '^(ldpi|mdpi|tvdpi|hdpi|xhdpi|xxhdpi|xxxhdpi|alldpi)$' | xargs)"
    local keys="$(echo $* | xargs -n 1 echo | \grep -E '^(devkeys)$' | xargs)"
    local apps="$(echo $* | xargs -n 1 echo | \grep -E -v '^(user|userdebug|eng|arm|x86|arm64|x86_64|ldpi|mdpi|tvdpi|hdpi|xhdpi|xxhdpi|xxxhdpi|alldpi|devkeys)$' | xargs)"


    if [ "$showHelp" != "" ]; then
      $(gettop)/build/make/tapasHelp.sh
      return
    fi

    if [ $(echo $arch | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple build archs supplied: $arch"
        return
    fi
    if [ $(echo $release | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple build releases supplied: $release"
        return
    fi
    if [ $(echo $variant | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple build variants supplied: $variant"
        return
    fi
    if [ $(echo $density | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple densities supplied: $density"
        return
    fi
    if [ $(echo $keys | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple keys supplied: $keys"
        return
    fi

    local product=aosp_arm
    case $arch in
      x86)    product=aosp_x86;;
      arm64)  product=aosp_arm64;;
      x86_64) product=aosp_x86_64;;
    esac
    if [ -n "$keys" ]; then
        product=${product/aosp_/aosp_${keys}_}
    fi;

    if [ -z "$variant" ]; then
        variant=eng
    fi
    if [ -z "$apps" ]; then
        apps=all
    fi
    if [ -z "$density" ]; then
        density=alldpi
    fi

    export TARGET_PRODUCT=$product
    export TARGET_RELEASE=$release
    export TARGET_BUILD_VARIANT=$variant
    export TARGET_BUILD_DENSITY=$density
    export TARGET_BUILD_TYPE=release
    export TARGET_BUILD_APPS=$apps

    build_build_var_cache
    set_stuff_for_environment
    printconfig
    destroy_build_var_cache
}

# Configures the build to build unbundled Android modules (APEXes).
# Run banchan with one or more module names (from apex{} modules).
function banchan()
{
    local showHelp="$(echo $* | xargs -n 1 echo | \grep -E '^(help)$' | xargs)"
    local product="$(echo $* | xargs -n 1 echo | \grep -E '^(.*_)?(arm|x86|arm64|riscv64|x86_64|arm64only|x86_64only)$' | xargs)"
    # TODO: Expand banchan to take release arguments (and update hmm() usage).
    local release="trunk_staging"
    local variant="$(echo $* | xargs -n 1 echo | \grep -E '^(user|userdebug|eng)$' | xargs)"
    local apps="$(echo $* | xargs -n 1 echo | \grep -E -v '^(user|userdebug|eng|(.*_)?(arm|x86|arm64|riscv64|x86_64))$' | xargs)"

    if [ "$showHelp" != "" ]; then
      $(gettop)/build/make/banchanHelp.sh
      return
    fi

    if [ -z "$product" ]; then
        product=arm64
    elif [ $(echo $product | wc -w) -gt 1 ]; then
        echo "banchan: Error: Multiple build archs or products supplied: $products"
        return
    fi
    if [ $(echo $release | wc -w) -gt 1 ]; then
        echo "banchan: Error: Multiple build releases supplied: $release"
        return
    fi
    if [ $(echo $variant | wc -w) -gt 1 ]; then
        echo "banchan: Error: Multiple build variants supplied: $variant"
        return
    fi
    if [ -z "$apps" ]; then
        echo "banchan: Error: No modules supplied"
        return
    fi

    case $product in
      arm)    product=module_arm;;
      x86)    product=module_x86;;
      arm64)  product=module_arm64;;
      riscv64) product=module_riscv64;;
      x86_64) product=module_x86_64;;
      arm64only)  product=module_arm64only;;
      x86_64only) product=module_x86_64only;;
    esac
    if [ -z "$variant" ]; then
        variant=eng
    fi

    export TARGET_PRODUCT=$product
    export TARGET_RELEASE=$release
    export TARGET_BUILD_VARIANT=$variant
    export TARGET_BUILD_DENSITY=alldpi
    export TARGET_BUILD_TYPE=release

    # This setup currently uses TARGET_BUILD_APPS just like tapas, but the use
    # case is different and it may diverge in the future.
    export TARGET_BUILD_APPS=$apps

    build_build_var_cache
    set_stuff_for_environment
    printconfig
    destroy_build_var_cache
}

function croot()
{
    local T=$(gettop)
    if [ "$T" ]; then
        if [ "$1" ]; then
            \cd $(gettop)/$1
        else
            \cd $(gettop)
        fi
    else
        echo "Couldn't locate the top of the tree.  Try setting TOP."
    fi
}

function _croot()
{
    local T=$(gettop)
    if [ "$T" ]; then
        local cur="${COMP_WORDS[COMP_CWORD]}"
        k=0
        for c in $(compgen -d ${T}/${cur}); do
            COMPREPLY[k++]=${c#${T}/}/
        done
    fi
}

function cproj()
{
    local TOPFILE=build/make/core/envsetup.mk
    local HERE=$PWD
    local T=
    while [ \( ! \( -f $TOPFILE \) \) -a \( $PWD != "/" \) ]; do
        T=$PWD
        if [ -f "$T/Android.mk" ]; then
            \cd $T
            return
        fi
        \cd ..
    done
    \cd $HERE
    echo "can't find Android.mk"
}

# Ensure that we're always using the adb in the tree. This works around the fact
# that bash caches $PATH lookups, so if you use adb before lunching/building the
# one in your tree, you'll continue to get /usr/bin/adb or whatever even after
# you have the one from your current tree on your path. Historically this would
# cause confusion because glinux had adb in /usr/bin/ by default, though that
# doesn't appear to be the case on my rodete hosts; it is however still the case
# that my Mac has /usr/local/bin/adb installed by default and on the default
# path.
function adb() {
    # We need `command which` because zsh has a built-in `which` that's more
    # like `type`.
    local ADB=$(command which adb)
    if [ -z "$ADB" ]; then
        echo "Command adb not found; try lunch (and building) first?"
        return 1
    fi
    run_tool_with_logging "ADB" $ADB "${@}"
}

function fastboot() {
    local FASTBOOT=$(command which fastboot)
    if [ -z "$FASTBOOT" ]; then
        echo "Command fastboot not found; try lunch (and building) first?"
        return 1
    fi
    # Support tool event logging for fastboot command.
    run_tool_with_logging "FASTBOOT" $FASTBOOT "${@}"
}

# communicate with a running device or emulator, set up necessary state,
# and run the hat command.
function runhat()
{
    # process standard adb options
    local adbTarget=""
    if [ "$1" = "-d" -o "$1" = "-e" ]; then
        adbTarget=$1
        shift 1
    elif [ "$1" = "-s" ]; then
        adbTarget="$1 $2"
        shift 2
    fi
    local adbOptions=${adbTarget}
    #echo adbOptions = ${adbOptions}

    # runhat options
    local targetPid=$1

    if [ "$targetPid" = "" ]; then
        echo "Usage: runhat [ -d | -e | -s serial ] target-pid"
        return
    fi

    # confirm hat is available
    if [ -z $(which hat) ]; then
        echo "hat is not available in this configuration."
        return
    fi

    # issue "am" command to cause the hprof dump
    local devFile=/data/local/tmp/hprof-$targetPid
    echo "Poking $targetPid and waiting for data..."
    echo "Storing data at $devFile"
    adb ${adbOptions} shell am dumpheap $targetPid $devFile
    echo "Press enter when logcat shows \"hprof: heap dump completed\""
    echo -n "> "
    read

    local localFile=/tmp/$$-hprof

    echo "Retrieving file $devFile..."
    adb ${adbOptions} pull $devFile $localFile

    adb ${adbOptions} shell rm $devFile

    echo "Running hat on $localFile"
    echo "View the output by pointing your browser at http://localhost:7000/"
    echo ""
    hat -JXmx512m $localFile
}

function godir () {
    if [[ -z "$1" ]]; then
        echo "Usage: godir <regex>"
        return
    fi
    local T=$(gettop)
    local FILELIST
    if [ ! "$OUT_DIR" = "" ]; then
        mkdir -p $OUT_DIR
        FILELIST=$OUT_DIR/filelist
    else
        FILELIST=$T/filelist
    fi
    if [[ ! -f $FILELIST ]]; then
        echo -n "Creating index..."
        (\cd $T; find . -wholename ./out -prune -o -wholename ./.repo -prune -o -type f > $FILELIST)
        echo " Done"
        echo ""
    fi
    local lines
    lines=($(\grep "$1" $FILELIST | sed -e 's/\/[^/]*$//' | sort | uniq))
    if [[ ${#lines[@]} = 0 ]]; then
        echo "Not found"
        return
    fi
    local pathname
    local choice
    if [[ ${#lines[@]} > 1 ]]; then
        while [[ -z "$pathname" ]]; do
            local index=1
            local line
            for line in ${lines[@]}; do
                printf "%6s %s\n" "[$index]" $line
                index=$(($index + 1))
            done
            echo
            echo -n "Select one: "
            unset choice
            read choice
            if [[ $choice -gt ${#lines[@]} || $choice -lt 1 ]]; then
                echo "Invalid choice"
                continue
            fi
            pathname=${lines[@]:$(($choice-1)):1}
        done
    else
        pathname=${lines[@]:0:1}
    fi
    \cd $T/$pathname
}

# Go to a specific module in the android tree, as cached in module-info.json. If any build change
# is made, and it should be reflected in the output, you should run 'refreshmod' first.
# Note: This function is in envsetup because changing the directory needs to happen in the current
# shell. All other functions that use module-info.json should be in build/soong/bin.
function gomod() {
    if [[ $# -ne 1 ]]; then
        echo "usage: gomod <module>" >&2
        return 1
    fi

    local path="$(pathmod $@)"
    if [ -z "$path" ]; then
        return 1
    fi
    cd $path
}

function _complete_android_module_names() {
    local word=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=( $(allmod | grep -E "^$word") )
}

function get_make_command()
{
    # If we're in the top of an Android tree, use soong_ui.bash instead of make
    if [ -f build/soong/soong_ui.bash ]; then
        # Always use the real make if -C is passed in
        for arg in "$@"; do
            if [[ $arg == -C* ]]; then
                echo command make
                return
            fi
        done
        echo build/soong/soong_ui.bash --make-mode
    else
        echo command make
    fi
}

function make()
{
    _wrap_build $(get_make_command "$@") "$@"
}

# Zsh needs bashcompinit called to support bash-style completion.
function enable_zsh_completion() {
    # Don't override user's options if bash-style completion is already enabled.
    if ! declare -f complete >/dev/null; then
        autoload -U compinit && compinit
        autoload -U bashcompinit && bashcompinit
    fi
}

function validate_current_shell() {
    local current_sh="$(ps -o command -p $$)"
    case "$current_sh" in
        *bash*)
            function check_type() { type -t "$1"; }
            ;;
        *zsh*)
            function check_type() { type "$1"; }
            enable_zsh_completion ;;
        *)
            echo -e "WARNING: Only bash and zsh are supported.\nUse of other shell would lead to erroneous results."
            ;;
    esac
}

# Execute the contents of any vendorsetup.sh files we can find.
# Unless we find an allowed-vendorsetup_sh-files file, in which case we'll only
# load those.
#
# This allows loading only approved vendorsetup.sh files
function source_vendorsetup() {
    unset VENDOR_PYTHONPATH
    local T="$(gettop)"
    allowed=
    for f in $(cd "$T" && find -L device vendor product -maxdepth 4 -name 'allowed-vendorsetup_sh-files' 2>/dev/null | sort); do
        if [ -n "$allowed" ]; then
            echo "More than one 'allowed_vendorsetup_sh-files' file found, not including any vendorsetup.sh files:"
            echo "  $allowed"
            echo "  $f"
            return
        fi
        allowed="$T/$f"
    done

    allowed_files=
    [ -n "$allowed" ] && allowed_files=$(cat "$allowed")
    for dir in device vendor product; do
        for f in $(cd "$T" && test -d $dir && \
            find -L $dir -maxdepth 4 -name 'vendorsetup.sh' 2>/dev/null | sort); do

            if [[ -z "$allowed" || "$allowed_files" =~ $f ]]; then
                echo "including $f"; . "$T/$f"
            else
                echo "ignoring $f, not in $allowed"
            fi
        done
    done

    setup_cog_env_if_needed
}

function showcommands() {
    local T=$(gettop)
    if [[ -z "$TARGET_PRODUCT" ]]; then
        >&2 echo "TARGET_PRODUCT not set. Run lunch."
        return
    fi
    case $(uname -s) in
        Darwin)
            PREBUILT_NAME=darwin-x86
            ;;
        Linux)
            PREBUILT_NAME=linux-x86
            ;;
        *)
            >&2 echo Unknown host $(uname -s)
            return
            ;;
    esac
    OUT_DIR="$(_get_abs_build_var_cached OUT_DIR)"
    if [[ "$1" == "--regenerate" ]]; then
      shift 1
      NINJA_ARGS="-t commands $@" m
    else
      (cd $T && prebuilts/build-tools/$PREBUILT_NAME/bin/ninja \
          -f $OUT_DIR/combined-${TARGET_PRODUCT}.ninja \
          -t commands "$@")
    fi
}

# These functions used to be here but are now standalone scripts
# in build/soong/bin.  Unset these for the time being so the real
# script is picked up.
# TODO: Remove this some time after a suitable delay (maybe 2025?)
unset allmod
unset aninja
unset cgrep
unset core
unset coredump_enable
unset coredump_setup
unset dirmods
unset get_build_var
unset get_abs_build_var
unset getlastscreenshot
unset getprebuilt
unset getscreenshotpath
unset getsdcardpath
unset gettargetarch
unset ggrep
unset gogrep
unset hmm
unset installmod
unset is64bit
unset isviewserverstarted
unset jgrep
unset jsongrep
unset key_back
unset key_home
unset key_menu
unset ktgrep
unset m
unset mangrep
unset mgrep
unset mm
unset mma
unset mmm
unset mmma
unset outmod
unset overrideflags
unset owngrep
unset pathmod
unset pez
unset pygrep
unset qpid
unset rcgrep
unset refreshmod
unset resgrep
unset rsgrep
unset run_tool_with_logging
unset sepgrep
unset sgrep
unset startviewserver
unset stopviewserver
unset systemstack
unset syswrite
unset tomlgrep
unset treegrep

function aurora() {
    local device=""
    local build_type=""
    local gms_enabled=false
    local core_gms=false
    local vanilla_enabled=false

    for arg in "$@"; do
        case "$arg" in
            gms)
                if [[ "$gms_enabled" == true ]]; then
                    echo "Error: GMS already specified."
                    return 1
                fi
                if [[ "$vanilla_enabled" == true ]]; then
                    echo "Error: Cannot specify both GMS and vanilla."
                    return 1
                fi
                gms_enabled=true
                ;;
            core)
                if [[ "$gms_enabled" != true ]]; then
                    echo "Error: Core GMS variant specified without enabling GMS."
                    return 1
                fi
                core_gms=true
                ;;
            va|vanilla)
                if [[ "$vanilla_enabled" == true ]]; then
                    echo "Error: Vanilla already specified."
                    return 1
                fi
                if [[ "$gms_enabled" == true ]]; then
                    echo "Error: Cannot specify both GMS and vanilla."
                    return 1
                fi
                vanilla_enabled=true
                ;;
            user|userdebug|eng)
                if [[ -n "$build_type" ]]; then
                    echo "Error: Multiple build types specified ($build_type and $arg). Only one build type can be used."
                    return 1
                fi
                build_type="$arg"
                ;;
            *)
                if [[ -n "$device" ]]; then
                    echo "Error: Multiple device names detected ($device and $arg). Please specify only one device."
                    return 1
                fi
                device="$arg"
                ;;
        esac
    done

    if [ -z "$device" ]; then
        if [[ -n "$TARGET_PRODUCT" ]]; then
            device=$(echo "$TARGET_PRODUCT" | sed -E 's/aurora_([^_]+).*/\1/')
            echo "No argument found for device, using TARGET_PRODUCT as device: $device"
        else
            echo "Correct usage: aurora <device_codename> [build_type] [gms [core] | va]"
            echo "Available build types: user, userdebug, eng"
            echo "Available GMS variants: core"
            echo "Use 'va' or 'vanilla' for a non-GMS build."
            return 1
        fi
    fi

    if [ -z "$build_type" ]; then
        build_type="userdebug"
    fi

    if [[ "$gms_enabled" == true ]]; then
        export WITH_GMS=true
        if [[ "$core_gms" == true ]]; then
            export TARGET_CORE_GMS=true
        else
            export TARGET_CORE_GMS=false
        fi
    elif [[ "$vanilla_enabled" == true ]]; then
        export WITH_GMS=false
        unset TARGET_CORE_GMS
    else
        export WITH_GMS=false
        unset TARGET_CORE_GMS
    fi

    source "${ANDROID_BUILD_TOP}/vendor/aurora/vars/aosp_target_release"

    case "$build_type" in
        user|userdebug|eng)
            lunch aurora_"$device"-"$aosp_target_release"-"$build_type"
        ;;
        *)
            echo "Error: Invalid build type '$build_type'. Available options: user, userdebug, eng"
            return 1
        ;;
    esac

    ax_help
}

function ax_help() {
    local BOLD="\e[1m"
    local GREEN="\e[32m"
    local YELLOW="\e[33m"
    local CYAN="\e[36m"
    local RESET="\e[0m"

    echo -e "${BOLD}${GREEN}=========================================${RESET}"
    echo -e "${BOLD}${CYAN}          BUILDING INSTRUCTIONS          ${RESET}"
    echo -e "${BOLD}${GREEN}=========================================${RESET}"
    echo
    echo -e "Use ${YELLOW}aurora${RESET} instead of ${YELLOW}lunch${RESET}."
    echo
    echo -e "aurora Usage: ${YELLOW}aurora <device_codename> [user|userdebug|eng] [gms [core] | vanilla]${RESET}"
    echo
    echo -e "${BOLD}ax usage:${RESET} ${YELLOW}ax [-b|-fb|-br] [-j<num>] [user|eng|userdebug]${RESET}"
    echo
    echo -e "${BOLD}Build Types:${RESET}"
    echo -e "  ${YELLOW}-b${RESET}   ${CYAN}Bacon${RESET}"
    echo -e "  ${YELLOW}-fb${RESET}  ${CYAN}Fastboot${RESET}"
    echo -e "  ${YELLOW}-br${RESET}  ${CYAN}Brunch${RESET}"
    echo
    echo -e "${BOLD}Build Options:${RESET}"
    echo -e "  ${YELLOW}-j<num>${RESET}  ${CYAN}Job count${RESET}"
    echo -e "  ${YELLOW}user | eng | userdebug${RESET}  ${CYAN}Build variant${RESET}"
    echo
    echo -e "${BOLD}Defaults:${RESET}"
    echo -e "  ${YELLOW}Job count${RESET}  ${CYAN}-j$(nproc --all)${RESET}"
    echo -e "  ${YELLOW}Build variant${RESET}  ${CYAN}userdebug${RESET}"
    echo -e "  ${YELLOW}Build type${RESET}  ${CYAN}m${RESET}"
    echo -e "${BOLD}${GREEN}=========================================${RESET}"
}

function ax() {
    if [[ "$1" == "help" ]]; then
        ax_help
        return 0
    fi

    local jCount=""
    local cmd=""
    local variant=""
    local device=""

    for arg in "$@"; do
        if [[ "$arg" =~ ^-j[0-9]+$ ]]; then
            jCount="$arg"
        elif [[ "$arg" =~ ^-(b|fb|br)$ ]]; then
            cmd="${arg:1}"
        elif [[ "$arg" =~ ^(user|eng|userdebug)$ ]]; then
            variant="$arg"
        else
            device="$arg"
        fi
    done

    jCount="${jCount:--j$(nproc --all)}"

    if [[ -n "$device" ]]; then
        export TARGET_PRODUCT="aurora_$device"
        echo "Setting target device to $device"
    elif [[ -z "$TARGET_PRODUCT" ]]; then
        echo "Error: No device target set. Please use 'aurora' or 'lunch' to set the target device."
        return 1
    fi

    if [[ -n "$variant" ]]; then
        export TARGET_BUILD_VARIANT="$variant"
        echo "Setting build variant to $variant"
    fi

    m installclean

    if [[ -z "$cmd" ]]; then
        echo "Running default 'm' build with $jCount"
        m "$jCount"
        return
    fi

    if [[ "$cmd" == "br" ]]; then
        local targetDevice=$(echo "$TARGET_PRODUCT" | sed -E 's/aurora_([^_]+).*/\1/')
        echo "Running brunch for device: $targetDevice with $jCount"
        brunch "$targetDevice" "$TARGET_BUILD_VARIANT" "$jCount"
        return
    fi

    case "$cmd" in
        b)
            m bacon "$jCount"
            ;;
        fb)
            m updatepackage "$jCount"
            ;;
    esac
}

function auroraSync() {
    yes y | repo init -u https://github.com/auroraOSP/android.git -b lineage-23.1 --git-lfs
    repo sync --force-sync
}

# usage (buildInstallApp): biApp Launcher3QuickStep/SettingsGoogle etc
function biApp() {
    local package="$1"
    if [[ "$package" == "L3" ]]; then
        package="Launcher3QuickStep"
    elif [[ "$package" == "SG" ]]; then
        package="SettingsGoogle"
    fi
    m "$package"
    iApp "$package"
}

# usage (installApp): iApp Launcher3QuickStep/SettingsGoogle etc
function iApp() {
    local target_device="$(get_build_var TARGET_DEVICE)"
    local package="$1"
    if [[ "$package" == "L3" ]]; then
        package="TrebuchetQuickStep"
    elif [[ "$package" == "SG" ]]; then
        package="SettingsGoogle"
    fi
    local apk_path=$(find "out/target/product/$target_device/" \
        \( -path "*/system_ext/*" -o -path "*/product/*" -o -path "*/system/*" \) \
        -type f -name "$package.apk" -print -quit)

    if [[ -z "$apk_path" ]]; then
        echo "Error: APK for package '$package' not found in system_ext, product, or system directories."
        return 1
    fi

    echo "Installing: $apk_path"
    adb install "$apk_path"
}

# usage: biPart system_ext/system/product/vendor
function biPart() {
    local partition="$1"
    bPart "$partition"
    iPart "$partition"
}

# usage: bPart system_ext/system/product/vendor
function bPart() {
    local partition="$1"
    case "$partition" in
        system_ext)
            m systemextimage
            ;;
        product)
            m productimage
            ;;
        system)
            m systemimage
            ;;
        vendor)
            m vendorimage
            ;;
        *)
            echo "Error: Unknown partition '$partition'. Valid options: system_ext, product, system, vendor."
            return 1
            ;;
    esac
}

# usage: iPart system_ext/system/product/vendor
function iPart() {
    local partition="$1"
    local target_device="$(get_build_var TARGET_DEVICE)"
    local img_path
    case "$partition" in
        system_ext|product|system|vendor)
            img_path="out/target/product/$target_device/$partition.img"
            ;;
        *)
            echo "Error: Unknown partition '$partition'. Valid options: system_ext, product, system, vendor."
            return 1
            ;;
    esac
    if [[ ! -f "$img_path" ]]; then
        echo "Error: Image for partition '$partition' not found at $img_path."
        return 1
    fi
    echo "Flashing $partition image: $img_path"
    adb reboot fastboot
    fastboot flash "$partition" "$img_path" && fastboot reboot
}

function setup_ccache() {
    if [ -z "${CCACHE_EXEC}" ]; then
        if command -v ccache &>/dev/null; then
            export USE_CCACHE=1
            export CCACHE_EXEC=$(command -v ccache)
            [ -z "${CCACHE_DIR}" ] && export CCACHE_DIR="$HOME/.ccache"
            echo "ccache directory found, CCACHE_DIR set to: $CCACHE_DIR" >&2

            CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-40G}"
            DIRECT_MODE="${DIRECT_MODE:-false}"

            $CCACHE_EXEC -o compression=true -o direct_mode="${DIRECT_MODE}" -M "${CCACHE_MAXSIZE}" \
                && echo "ccache enabled, CCACHE_EXEC set to: $CCACHE_EXEC, CCACHE_MAXSIZE set to: $CCACHE_MAXSIZE, direct_mode set to: $DIRECT_MODE" >&2 \
                || echo "Warning: Could not set cache size limit. Please check ccache configuration." >&2

            if [ -d "$CCACHE_DIR" ]; then
                CURRENT_CCACHE_SIZE_BYTES=$(du -sb "$CCACHE_DIR" 2>/dev/null | awk '{print $1}')
                CURRENT_CCACHE_SIZE_GB=$(echo "$CURRENT_CCACHE_SIZE_BYTES" | awk '{printf "%.2f\n", $1 / 1000 / 1000 / 1000}')

                if [ -n "$CURRENT_CCACHE_SIZE_GB" ]; then
                    echo "Current ccache size is: ${CURRENT_CCACHE_SIZE_GB} GB" >&2
                else
                    echo "No cached files in ccache." >&2
                fi
            else
                echo "Warning: ccache directory does not exist: $CCACHE_DIR" >&2
            fi
        else
            echo "Error: ccache not found. Please install ccache." >&2
        fi
    fi
}

function generate_keys() {
    local subject="/C=US/ST=California/L=Los Angeles/O=auroraOS/OU=auroraOS/CN=auroraOS"
    echo "Subject string: $subject"
    local key_names=("${@}")
    if [ -d "$ANDROID_KEY_PATH" ]; then
        echo "Cleaning up $ANDROID_KEY_PATH while preserving .git..."
        find "$ANDROID_KEY_PATH" -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} +
    fi
    mkdir -p "$ANDROID_KEY_PATH"
    for key_name in "${key_names[@]}"; do
        if [ -f "$ANDROID_KEY_PATH/$key_name.pk8" ] || [ -f "$ANDROID_KEY_PATH/$key_name.x509.pem" ]; then
            echo "Deleting existing files for $key_name..."
            rm -f "$ANDROID_KEY_PATH/$key_name.pk8" "$ANDROID_KEY_PATH/$key_name.x509.pem"
        fi
        echo "Executing make_key for $key_name without password..."
        echo "" | ./development/tools/make_key "$ANDROID_KEY_PATH/$key_name" "$subject"
    done
}

function show_help() {
    echo "Usage: gk [option]"
    echo ""
    echo "Options:"
    echo "  -s          Generate keys for simple signing"
    echo "  -h, --help  Show generate keys instructions"
}

function gk() {
    local mode="$1"
    case "$mode" in
        -h|--help)
            show_help
            return 0
            ;;
        -s)
            local key_names=("nfc" "bluetooth" "media" "networkstack" "platform" "releasekey" "sdk_sandbox" "shared" "testkey" "verifiedboot")
            ;;
        *)
            show_help
            return 0
            ;;
    esac
    echo "Generating keys..."
    generate_keys "${key_names[@]}"
    echo "PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/aurora-priv/keys/releasekey" > vendor/aurora-priv/keys/keys.mk
    bazel_build_content="filegroup(
    name = \"android_certificate_directory\",
    srcs = glob([
        \"*.pk8\",
        \"*.pem\",
    ]),
    visibility = [\"//visibility:public\"],
)"
    echo "$bazel_build_content" > vendor/aurora-priv/keys/BUILD.bazel
    if [ "$mode" == "-f" ]; then
        local subject="/C=US/ST=California/L=Los Angeles/O=auroraOS/OU=auroraOS/CN=auroraOS"
        cp ./development/tools/make_key $ANDROID_KEY_PATH/
        sed -i 's|2048|4096|g' $ANDROID_KEY_PATH/make_key
        for apex in com.android.adbd com.android.adservices com.android.adservices.api com.android.appsearch com.android.art com.android.bluetooth com.android.btservices com.android.cellbroadcast com.android.compos com.android.configinfrastructure com.android.connectivity.resources com.android.conscrypt com.android.devicelock com.android.extservices com.android.graphics.pdf com.android.hardware.biometrics.face.virtual com.android.hardware.biometrics.fingerprint.virtual com.android.hardware.boot com.android.hardware.cas com.android.hardware.wifi com.android.healthfitness com.android.hotspot2.osulogin com.android.i18n com.android.ipsec com.android.media com.android.media.swcodec com.android.mediaprovider com.android.nearby.halfsheet com.android.networkstack.tethering com.android.neuralnetworks com.android.ondevicepersonalization com.android.os.statsd com.android.permission com.android.resolv com.android.rkpd com.android.runtime com.android.safetycenter.resources com.android.scheduling com.android.sdkext com.android.support.apexer com.android.telephony com.android.telephonymodules com.android.tethering com.android.tzdata com.android.uwb com.android.uwb.resources com.android.virt com.android.vndk.current com.android.vndk.current.on_vendor com.android.wifi com.android.wifi.dialog com.android.wifi.resources com.google.pixel.camera.hal com.google.pixel.vibrator.hal com.qorvo.uwb; do
            if [ -f "$ANDROID_KEY_PATH/$apex.pk8" ] || [ -f "$ANDROID_KEY_PATH/$apex.x509.pem" ]; then
                echo "Deleting existing files for $apex..."
                rm -f "$ANDROID_KEY_PATH/$apex.pk8" "$ANDROID_KEY_PATH/$apex.x509.pem"
            fi
            echo "" | $ANDROID_KEY_PATH/make_key $ANDROID_KEY_PATH/$apex "$subject"
            openssl pkcs8 -in $ANDROID_KEY_PATH/$apex.pk8 -inform DER -nocrypt -out $ANDROID_KEY_PATH/$apex.pem
        done
    fi
}

function remove_keys() {
    local key_mk="vendor/aurora-priv/keys/keys.mk"
    local build_bazel="vendor/aurora-priv/keys/BUILD.bazel"
    if [ -f "$key_mk" ]; then
        echo "Removing $key_mk..."
        sudo rm -f "$key_mk"
    else
        echo "$key_mk does not exist."
    fi
    if [ -f "$build_bazel" ]; then
        echo "Removing $build_bazel..."
        sudo rm -f "$build_bazel"
    else
        echo "$build_bazel does not exist."
    fi
}

function rcleanup() {
    echo "Generating list of current repositories from the manifest files..."

    # Initialize current_repos.txt
    > current_repos.txt

    # Aggregate project names from manifest files in .repo/manifests
    for manifest in .repo/manifests/default.xml .repo/manifests/snippets/lineage.xml .repo/manifests/snippets/pixel.xml .repo/manifests/snippets/aurora.xml;
    do
        if [ -f "$manifest" ]; then
            grep 'name=' "$manifest" | sed -e 's/.*name="\([^"]*\)".*/\1/' >> current_repos.txt
        fi
    done

    # Append project names from .repo/local_manifests/*.xml if they exist
    if ls .repo/local_manifests/*.xml 1> /dev/null 2>&1; then
        grep 'name=' .repo/local_manifests/*.xml | sed -e 's/.*name="\([^"]*\)".*/\1/' >> current_repos.txt
    fi

    echo "Navigating to .repo/project-objects directory..."
    cd .repo/project-objects || { echo "Failed to navigate to .repo/project-objects"; exit 1; }

    echo "Listing all repositories in .repo/project-objects..."
    find . -type d -name "*.git" | sed 's|^\./||' | sed 's|\.git$||' > all_repos.txt

    echo "Identifying old repositories..."
    old_repos=$(comm -23 <(sort all_repos.txt) <(sort ../../current_repos.txt))

    if [ -z "$old_repos" ]; then
        echo "No old repositories to remove."
        rm ../../current_repos.txt
        rm all_repos.txt
        croot
        return
    fi

    echo "The following repositories will be removed:"
    echo "$old_repos"

    read -p "Do you want to proceed with the removal? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Removal cancelled."
        rm ../../current_repos.txt
        rm all_repos.txt
        croot
        return
    fi

    echo "Removing old repositories..."
    for repo in $old_repos; do
        echo "Removing old repository: $repo"
        rm -rf "$repo.git"
    done

    echo "Removing temporary pack files..."
    find . -type f -name "tmp_pack_*" -exec rm -f {} +

    echo "Performing garbage collection on all repositories..."
    repo forall -c 'git gc --prune=now --aggressive'

    echo "Cleaning up temporary files..."
    rm ../../current_repos.txt
    rm all_repos.txt

    echo "Cleanup complete."

    croot
}

function setup_keys() {
    if [[ ! -d vendor/aurora-priv/keys ]]; then
        gk -s
    fi
}

function generate_host_overrides() {
    export BUILD_USERNAME=android-build
    HEX=$(openssl rand -hex 8)
    ALPHA=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)
    export BUILD_HOSTNAME="r-${HEX}-${ALPHA}"
    echo "BUILD_USERNAME=$BUILD_USERNAME"
    echo "BUILD_HOSTNAME=$BUILD_HOSTNAME"
}

function cpo {
    local device="$1"
    local output_dir="out/target/product/$device"
    local base_dest_dir="$HOME/ROM"

    local latest_zip
    latest_zip=$(ls -t "$output_dir"/*.zip 2>/dev/null | head -n 1)

    if [[ -z "$latest_zip" ]]; then
        echo "No zip file found in $output_dir."
        return 1
    fi

    mkdir -p "$base_dest_dir"
    cp "$latest_zip" "$base_dest_dir" && echo "Copied $(basename "$latest_zip") to $base_dest_dir"

    if [[ "$latest_zip" == *GMS* ]]; then
        local dest_dir="$base_dest_dir/GMS"
        mkdir -p "$dest_dir"
        cp "$output_dir/GMS/$device.json" "$dest_dir" && echo "Copied $device.json from GMS folder"
    elif [[ "$latest_zip" == *VANILLA* ]]; then
        local dest_dir="$base_dest_dir/VANILLA"
        mkdir -p "$dest_dir"
        cp "$output_dir/VANILLA/$device.json" "$dest_dir" && echo "Copied $device.json from VANILLA folder"
    else
        echo "Neither GMS nor VANILLA detected in zip name."
    fi
}

function bpx() {
    function get_devices() {
        case "$1" in
            "6") echo "raven oriole bluejay" ;;
            "7") echo "cheetah panther" ;;
            *) echo "oriole raven bluejay panther cheetah" ;;
        esac
    }

    local devices
    devices=$(get_devices "$1")
    local base_dir="$HOME/ROM"

    for device in $devices; do
        local gms_zip="$base_dir/auroraOS-*GMS-$device.zip"
        local vanilla_zip="$base_dir/auroraOS-*VANILLA-$device.zip"

        if ls $gms_zip &>/dev/null && ls $vanilla_zip &>/dev/null; then
            echo "Both GMS and VANILLA builds exist for $device. Skipping..."
            continue
        fi

        if ! ls $vanilla_zip &>/dev/null; then
            echo "VANILLA build missing for $device. Building..."
            aurora "$device" va
            ax -br "$device"
            cpo "$device"
        else
            echo "VANILLA build already exists for $device. Skipping Vanilla..."
        fi

        if ! ls $gms_zip &>/dev/null; then
            echo "GMS build missing for $device. Building..."
            aurora "$device" gms
            ax -br "$device"
            cpo "$device"
        else
            echo "GMS build already exists for $device. Skipping GMS..."
        fi
    done
}

function initPixelRoomService() {
    local ROOM_DIR="$(pwd)"
    local MANIFESTS_DIR="$ROOM_DIR/.repo/local_manifests"
    local ROOM_URL="https://raw.githubusercontent.com/auroraOSP/roomservice_pixels/refs/heads/main/roomservice.xml"
    local OUTPUT_FILE="$MANIFESTS_DIR/roomservice.xml"

    echo "[*] Starting pixel room service..."

    if [ ! -d "$MANIFESTS_DIR" ]; then
        mkdir -p "$MANIFESTS_DIR" || { echo "[!] Failed to create directory."; exit 1; }
    fi

    if [ -f "$OUTPUT_FILE" ]; then
        echo "[*] Backing up existing roomservice.xml"
        cp "$OUTPUT_FILE" "$OUTPUT_FILE.bak" || { echo "[!] Backup failed."; exit 1; }
    fi

    echo "[*] Downloading roomservice.xml..."
    if curl -fsSL "$ROOM_URL" -o "$OUTPUT_FILE"; then
        echo "[✓] roomservice.xml successfully written to $OUTPUT_FILE"
    else
        echo "[!] Failed to fetch roomservice.xml"
        exit 1
    fi
}

function rbr() {
    set +m

    local ROOT_DIR="$(pwd)"
    local AURORA_MANIFEST="$ROOT_DIR/android/snippets/aurora.xml"
    local ROOMSERVICE_MANIFEST="$ROOT_DIR/.repo/local_manifests/roomservice.xml"
    local TARGET_BRANCH="lineage-23.1"
    local MAX_JOBS=12

    local UPSTREAM_REMOTE="aurora"
    local UPSTREAM_DEVICES_REMOTE="aurora_devices"

    local REBASE_AURORA=true
    local REBASE_DEVICES=true

    case "$1" in
        -m) REBASE_DEVICES=false ;;
        -d) REBASE_AURORA=false ;;
        -a|""|*) ;;
    esac

    local TMP_REPO_LIST
    TMP_REPO_LIST=$(mktemp)

    extract_projects_from_manifest() {
        local manifest_file="$1"
        local remote_name="$2"

        grep '<project ' "$manifest_file" | \
            grep "remote=\"$remote_name\"" | \
            sed -n "s/.*path=\"\([^\"]*\\)\".*name=\"\([^\"]*\)\".*/\1|\2|$remote_name/p"
    }

    if $REBASE_AURORA && [[ -f "$AURORA_MANIFEST" ]]; then
        extract_projects_from_manifest "$AURORA_MANIFEST" "$UPSTREAM_REMOTE" >> "$TMP_REPO_LIST"
    fi

    if $REBASE_DEVICES && [[ -f "$ROOMSERVICE_MANIFEST" ]]; then
        extract_projects_from_manifest "$ROOMSERVICE_MANIFEST" "$UPSTREAM_DEVICES_REMOTE" >> "$TMP_REPO_LIST"
    fi

    local -a SUCCESS_REPOS=()
    local -a SKIPPED_REPOS=()
    local -a FAILED_REPOS=()
    local TMP_DIR
    TMP_DIR=$(mktemp -d)

    process_repo() {
        local REPO_PATH="$1"
        local REPO_NAME="$2"
        local PUSH_REMOTE="$3"

        echo "[INFO] Processing $REPO_PATH ($REPO_NAME) with remote '$PUSH_REMOTE'..."

        if [[ ! -d "$ROOT_DIR/$REPO_PATH" ]]; then
            echo "[WARN] Directory $REPO_PATH not found, skipping."
            echo "SKIPPED $REPO_PATH" > "$TMP_DIR/${REPO_PATH//\//_}.status"
            return
        fi

        echo "[INFO] Fetching from LineageOS/$REPO_NAME..."
        if ! git -C "$ROOT_DIR/$REPO_PATH" fetch "https://github.com/LineageOS/$REPO_NAME" "$TARGET_BRANCH" 2>/dev/null; then
            echo "[WARN] Branch '$TARGET_BRANCH' not found in LineageOS/$REPO_NAME, skipping."
            echo "SKIPPED $REPO_PATH" > "$TMP_DIR/${REPO_PATH//\//_}.status"
            return
        fi

        echo "[INFO] Rebasing onto LineageOS/$TARGET_BRANCH..."
        if ! git -C "$ROOT_DIR/$REPO_PATH" rebase FETCH_HEAD 2>/dev/null; then
            echo "[ERROR] Rebase failed or conflict in $REPO_PATH."
            git -C "$ROOT_DIR/$REPO_PATH" rebase --abort >/dev/null 2>&1
            echo "FAILED $REPO_PATH" > "$TMP_DIR/${REPO_PATH//\//_}.status"
            return
        fi

        echo "[INFO] Pushing to $PUSH_REMOTE/$TARGET_BRANCH..."
        if ! git -C "$ROOT_DIR/$REPO_PATH" push -f --set-upstream "$PUSH_REMOTE" "$TARGET_BRANCH" 2>/dev/null; then
            echo "[INFO] Push failed or unnecessary for $REPO_PATH"
            echo "SKIPPED $REPO_PATH" > "$TMP_DIR/${REPO_PATH//\//_}.status"
            return
        fi

        echo "[OK] Successfully rebased and pushed: $REPO_PATH"
        echo "SUCCESS $REPO_PATH" > "$TMP_DIR/${REPO_PATH//\//_}.status"
    }

    TOTAL_REPOS=$(wc -l < "$TMP_REPO_LIST")
    PROCESSED=0
    JOBS=0

    echo "[INFO] Performing rebase operations"

    while IFS='|' read -r REPO_PATH REPO_NAME PUSH_REMOTE; do
        PROCESSED=$((PROCESSED + 1))
        echo "Processing $PROCESSED/$TOTAL_REPOS: $REPO_PATH..."

        { (process_repo "$REPO_PATH" "$REPO_NAME" "$PUSH_REMOTE" > "$TMP_DIR/${REPO_PATH//\//_}.log" 2>&1) & } 2>/dev/null

        JOBS=$((JOBS + 1))
        if [[ "$JOBS" -ge "$MAX_JOBS" ]]; then
            wait -n
            JOBS=$((JOBS - 1))
        fi
    done < "$TMP_REPO_LIST"

    wait

    for STATUS_FILE in "$TMP_DIR"/*.status; do
        [[ ! -f "$STATUS_FILE" ]] && continue
        RESULT=$(cut -d' ' -f1 "$STATUS_FILE")
        REPO=$(cut -d' ' -f2- "$STATUS_FILE")
        case "$RESULT" in
            SUCCESS) SUCCESS_REPOS+=("$REPO") ;;
            SKIPPED) SKIPPED_REPOS+=("$REPO") ;;
            FAILED)  FAILED_REPOS+=("$REPO") ;;
        esac
    done

    rm -rf "$TMP_REPO_LIST" "$TMP_DIR"

    echo ""
    echo "[DONE] All repositories processed."
    echo ""
    echo "===== SUMMARY ====="
    echo "Successful: ${#SUCCESS_REPOS[@]}"
    echo "Failed:     ${#FAILED_REPOS[@]}"
    echo "Skipped:    ${#SKIPPED_REPOS[@]}"

    if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
        echo ""
        echo "Failed Repos:"
        printf ' - %s\n' "${FAILED_REPOS[@]}"
    fi

    if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then
        echo ""
        echo "Skipped Repos:"
        printf ' - %s\n' "${SKIPPED_REPOS[@]}"
    fi
}

setup_keys
setup_ccache
validate_current_shell
set_global_paths
source_vendorsetup
addcompletions
ax_help
generate_host_overrides

if [[ "$USE_LEFTOVERS" -eq 1 ]]; then
  leftovers
fi

export ANDROID_BUILD_TOP=$(gettop)
export ANDROID_KEY_PATH="$ANDROID_BUILD_TOP/vendor/aurora-priv/keys"

. $ANDROID_BUILD_TOP/vendor/aurora/build/envsetup.sh
