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


# Help
function hmm() {
cat <<EOF

Run "m help" for help with the build system itself.

Invoke ". build/envsetup.sh" from your shell to add the following functions to your environment:
- lunch:      lunch <product_name>-<release_type>-<build_variant>
              Selects <product_name> as the product to build, and <build_variant> as the variant to
              build, and stores those selections in the environment to be read by subsequent
              invocations of 'm' etc.
- tapas:      tapas [<App1> <App2> ...] [arm|x86|arm64|x86_64] [eng|userdebug|user]
              Sets up the build environment for building unbundled apps (APKs).
- banchan:    banchan <module1> [<module2> ...] \\
                      [arm|x86|arm64|riscv64|x86_64|arm64_only|x86_64only] [eng|userdebug|user]
              Sets up the build environment for building unbundled modules (APEXes).
- croot:      Changes directory to the top of the tree, or a subdirectory thereof.
- m:          Makes from the top of the tree.
- mm:         Builds and installs all of the modules in the current directory, and their
              dependencies.
- mmm:        Builds and installs all of the modules in the supplied directories, and their
              dependencies.
              To limit the modules being built use the syntax: mmm dir/:target1,target2.
- mma:        Same as 'mm'
- mmma:       Same as 'mmm'
- provision:  Flash device with all required partitions. Options will be passed on to fastboot.
- cgrep:      Greps on all local C/C++ files.
- ggrep:      Greps on all local Gradle files.
- gogrep:     Greps on all local Go files.
- jgrep:      Greps on all local Java files.
- jsongrep:   Greps on all local Json files.
- ktgrep:     Greps on all local Kotlin files.
- resgrep:    Greps on all local res/*.xml files.
- mangrep:    Greps on all local AndroidManifest.xml files.
- mgrep:      Greps on all local Makefiles and *.bp files.
- owngrep:    Greps on all local OWNERS files.
- rsgrep:     Greps on all local Rust files.
- sepgrep:    Greps on all local sepolicy files.
- sgrep:      Greps on all local source files.
- tomlgrep:   Greps on all local Toml files.
- pygrep:     Greps on all local Python files.
- godir:      Go to the directory containing a file.
- allmod:     List all modules.
- gomod:      Go to the directory containing a module.
- bmod:       Get the Bazel label of a Soong module if it is converted with bp2build.
- pathmod:    Get the directory containing a module.
- outmod:     Gets the location of a module's installed outputs with a certain extension.
- dirmods:    Gets the modules defined in a given directory.
- installmod: Adb installs a module's built APK.
- refreshmod: Refresh list of modules for allmod/gomod/pathmod/outmod/installmod.
- syswrite:   Remount partitions (e.g. system.img) as writable, rebooting if necessary.

EOF

    __print_lineage_functions_help

cat <<EOF

Environment options:
- SANITIZE_HOST: Set to 'address' to use ASAN for all host modules.
- ANDROID_QUIET_BUILD: set to 'true' to display only the essential messages.

Look at the source to view more functions. The complete list is:
EOF
    local T=$(gettop)
    local A=""
    local i
    for i in `cat $T/build/envsetup.sh $T/vendor/lineage/build/envsetup.sh | sed -n "/^[[:blank:]]*function /s/function \([a-z_]*\).*/\1/p" | sort | uniq`; do
      A="$A $i"
    done
    echo $A
}

# Get all the build variables needed by this script in a single call to the build system.
function build_build_var_cache()
{
    local T=$(gettop)
    # Grep out the variable names from the script.
    cached_vars=(`cat $T/build/envsetup.sh $T/vendor/lineage/build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/get_build_var/) print $(i+1)}' | sort -u | tr '\n' ' '`)
    cached_abs_vars=(`cat $T/build/envsetup.sh $T/vendor/lineage/build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/get_abs_build_var/) print $(i+1)}' | sort -u | tr '\n' ' '`)
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
function get_abs_build_var()
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
function get_build_var()
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

# check to see if the supplied product is one we can build
function check_product()
{
    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    if (echo -n $1 | grep -q -e "^lineage_") ; then
        LINEAGE_BUILD=$(echo -n $1 | sed -e 's/^lineage_//g')
    else
        LINEAGE_BUILD=
    fi
    export LINEAGE_BUILD

        TARGET_PRODUCT=$1 \
        TARGET_RELEASE=$2 \
        TARGET_BUILD_VARIANT= \
        TARGET_BUILD_TYPE= \
        TARGET_BUILD_APPS= \
        get_build_var TARGET_DEVICE > /dev/null
    # hide successful answers, but allow the errors to show
}

VARIANT_CHOICES=(user userdebug eng)

# check to see if the supplied variant is valid
function check_variant()
{
    local v
    for v in ${VARIANT_CHOICES[@]}
    do
        if [ "$v" = "$1" ]
        then
            return 0
        fi
    done
    return 1
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
    ANDROID_LUNCH_BUILD_PATHS=$(get_abs_build_var SOONG_HOST_OUT_EXECUTABLES)
    ANDROID_LUNCH_BUILD_PATHS+=:$(get_abs_build_var HOST_OUT_EXECUTABLES)

    # Append llvm binutils prebuilts path to ANDROID_LUNCH_BUILD_PATHS.
    local ANDROID_LLVM_BINUTILS=$(get_abs_build_var ANDROID_CLANG_PREBUILTS)/llvm-binutils-stable
    ANDROID_LUNCH_BUILD_PATHS+=:$ANDROID_LLVM_BINUTILS

    # Set up ASAN_SYMBOLIZER_PATH for SANITIZE_HOST=address builds.
    export ASAN_SYMBOLIZER_PATH=$ANDROID_LLVM_BINUTILS/llvm-symbolizer

    # Append asuite prebuilts path to ANDROID_LUNCH_BUILD_PATHS.
    local os_arch=$(get_build_var HOST_PREBUILT_TAG)
    ANDROID_LUNCH_BUILD_PATHS+=:$T/prebuilts/asuite/acloud/$os_arch
    ANDROID_LUNCH_BUILD_PATHS+=:$T/prebuilts/asuite/aidegen/$os_arch
    ANDROID_LUNCH_BUILD_PATHS+=:$T/prebuilts/asuite/atest/$os_arch

    export ANDROID_JAVA_HOME=$(get_abs_build_var ANDROID_JAVA_HOME)
    export JAVA_HOME=$ANDROID_JAVA_HOME
    export ANDROID_JAVA_TOOLCHAIN=$(get_abs_build_var ANDROID_JAVA_TOOLCHAIN)
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
    export ANDROID_PRODUCT_OUT=$(get_abs_build_var PRODUCT_OUT)
    export OUT=$ANDROID_PRODUCT_OUT

    unset ANDROID_HOST_OUT
    export ANDROID_HOST_OUT=$(get_abs_build_var HOST_OUT)

    unset ANDROID_SOONG_HOST_OUT
    export ANDROID_SOONG_HOST_OUT=$(get_abs_build_var SOONG_HOST_OUT)

    unset ANDROID_HOST_OUT_TESTCASES
    export ANDROID_HOST_OUT_TESTCASES=$(get_abs_build_var HOST_OUT_TESTCASES)

    unset ANDROID_TARGET_OUT_TESTCASES
    export ANDROID_TARGET_OUT_TESTCASES=$(get_abs_build_var TARGET_OUT_TESTCASES)

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
        export PATH=${PATH/$ANDROID_GLOBAL_BUILD_PATHS/}
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
    get_build_var report_config
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
      prebuilts/bazel/common/bazel-complete.bash
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

    if should_add_completion bit ; then
        complete -C "bit --tab" bit
    fi
    if [ -z "$ZSH_VERSION" ]; then
        # Doesn't work in zsh.
        complete -o nospace -F _croot croot
        # TODO(b/244559459): Support b autocompletion for zsh
        complete -F _bazel__complete -o nospace b
    fi
    complete -F _lunch lunch

    complete -F _complete_android_module_names pathmod
    complete -F _complete_android_module_names gomod
    complete -F _complete_android_module_names outmod
    complete -F _complete_android_module_names installmod
    complete -F _complete_android_module_names bmod
    complete -F _complete_android_module_names m
}

function multitree_lunch_help()
{
    echo "usage: lunch PRODUCT-RELEASE-VARIANT" 1>&2
    echo "    Set up android build environment based on a product short name and variant" 1>&2
    echo 1>&2
    echo "lunch COMBO_FILE VARIANT" 1>&2
    echo "    Set up android build environment based on a specific lunch combo file" 1>&2
    echo "    and variant." 1>&2
    echo 1>&2
    echo "lunch --print [CONFIG]" 1>&2
    echo "    Print the contents of a configuration.  If CONFIG is supplied, that config" 1>&2
    echo "    will be flattened and printed.  If CONFIG is not supplied, the currently" 1>&2
    echo "    selected config will be printed.  Returns 0 on success or nonzero on error." 1>&2
    echo 1>&2
    echo "lunch --list" 1>&2
    echo "    List all possible combo files available in the current tree" 1>&2
    echo 1>&2
    echo "lunch --help" 1>&2
    echo "lunch -h" 1>&2
    echo "    Prints this message." 1>&2
}

function multitree_lunch()
{
    local code
    local results
    # Lunch must be run in the topdir, but this way we get a clear error
    # message, instead of FileNotFound.
    local T=$(multitree_gettop)
    if [ -z "$T" ]; then
      _multitree_lunch_error
      return 1
    fi
    if $(echo "$1" | grep -q '^-') ; then
        # Calls starting with a -- argument are passed directly and the function
        # returns with the lunch.py exit code.
        "${T}/orchestrator/build/orchestrator/core/lunch.py" "$@"
        code=$?
        if [[ $code -eq 2 ]] ; then
          echo 1>&2
          multitree_lunch_help
          return $code
        elif [[ $code -ne 0 ]] ; then
          return $code
        fi
    else
        # All other calls go through the --lunch variant of lunch.py
        results=($(${T}/orchestrator/build/orchestrator/core/lunch.py --lunch "$@"))
        code=$?
        if [[ $code -eq 2 ]] ; then
          echo 1>&2
          multitree_lunch_help
          return $code
        elif [[ $code -ne 0 ]] ; then
          return $code
        fi

        export TARGET_BUILD_COMBO=${results[0]}
        export TARGET_BUILD_VARIANT=${results[1]}
    fi
}

function choosetype()
{
    echo "Build type choices are:"
    echo "     1. release"
    echo "     2. debug"
    echo

    local DEFAULT_NUM DEFAULT_VALUE
    DEFAULT_NUM=1
    DEFAULT_VALUE=release

    export TARGET_BUILD_TYPE=
    local ANSWER
    while [ -z $TARGET_BUILD_TYPE ]
    do
        echo -n "Which would you like? ["$DEFAULT_NUM"] "
        if [ -z "$1" ] ; then
            read ANSWER
        else
            echo $1
            ANSWER=$1
        fi
        case $ANSWER in
        "")
            export TARGET_BUILD_TYPE=$DEFAULT_VALUE
            ;;
        1)
            export TARGET_BUILD_TYPE=release
            ;;
        release)
            export TARGET_BUILD_TYPE=release
            ;;
        2)
            export TARGET_BUILD_TYPE=debug
            ;;
        debug)
            export TARGET_BUILD_TYPE=debug
            ;;
        *)
            echo
            echo "I didn't understand your response.  Please try again."
            echo
            ;;
        esac
        if [ -n "$1" ] ; then
            break
        fi
    done

    build_build_var_cache
    set_stuff_for_environment
    destroy_build_var_cache
}

#
# This function isn't really right:  It chooses a TARGET_PRODUCT
# based on the list of boards.  Usually, that gets you something
# that kinda works with a generic product, but really, you should
# pick a product by name.
#
function chooseproduct()
{
    local default_value
    if [ "x$TARGET_PRODUCT" != x ] ; then
        default_value=$TARGET_PRODUCT
    else
        default_value=aosp_arm
    fi

    export TARGET_BUILD_APPS=
    export TARGET_PRODUCT=
    local ANSWER
    while [ -z "$TARGET_PRODUCT" ]
    do
        echo -n "Which product would you like? [$default_value] "
        if [ -z "$1" ] ; then
            read ANSWER
        else
            echo $1
            ANSWER=$1
        fi

        if [ -z "$ANSWER" ] ; then
            export TARGET_PRODUCT=$default_value
        else
            if check_product $ANSWER
            then
                export TARGET_PRODUCT=$ANSWER
            else
                echo "** Not a valid product: $ANSWER"
            fi
        fi
        if [ -n "$1" ] ; then
            break
        fi
    done

    build_build_var_cache
    set_stuff_for_environment
    destroy_build_var_cache
}

function choosevariant()
{
    echo "Variant choices are:"
    local index=1
    local v
    for v in ${VARIANT_CHOICES[@]}
    do
        # The product name is the name of the directory containing
        # the makefile we found, above.
        echo "     $index. $v"
        index=$(($index+1))
    done

    local default_value=eng
    local ANSWER

    export TARGET_BUILD_VARIANT=
    while [ -z "$TARGET_BUILD_VARIANT" ]
    do
        echo -n "Which would you like? [$default_value] "
        if [ -z "$1" ] ; then
            read ANSWER
        else
            echo $1
            ANSWER=$1
        fi

        if [ -z "$ANSWER" ] ; then
            export TARGET_BUILD_VARIANT=$default_value
        elif (echo -n $ANSWER | grep -q -e "^[0-9][0-9]*$") ; then
            if [ "$ANSWER" -le "${#VARIANT_CHOICES[@]}" ] ; then
                export TARGET_BUILD_VARIANT=${VARIANT_CHOICES[@]:$(($ANSWER-1)):1}
            fi
        else
            if check_variant $ANSWER
            then
                export TARGET_BUILD_VARIANT=$ANSWER
            else
                echo "** Not a valid variant: $ANSWER"
            fi
        fi
        if [ -n "$1" ] ; then
            break
        fi
    done
}

function choosecombo()
{
    choosetype $1

    echo
    echo
    chooseproduct $2

    echo
    echo
    choosevariant $3

    echo
    build_build_var_cache
    set_stuff_for_environment
    printconfig
    destroy_build_var_cache
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
    choices=$(TARGET_BUILD_APPS= TARGET_PRODUCT= TARGET_RELEASE= TARGET_BUILD_VARIANT= get_build_var COMMON_LUNCH_CHOICES 2>/dev/null)
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

function lunch()
{
    local answer

    if [[ $# -gt 1 ]]; then
        echo "usage: lunch [target]" >&2
        return 1
    fi

    local used_lunch_menu=0

    if [ "$1" ]; then
        answer=$1
    else
        print_lunch_menu
        echo "Which would you like? [aosp_cf_x86_64_phone-trunk_staging-eng]"
        echo -n "Pick from common choices above (e.g. 13) or specify your own (e.g. aosp_barbet-trunk_staging-eng): "
        read answer
        used_lunch_menu=1
    fi

    local selection=

    if [ -z "$answer" ]
    then
        selection=aosp_cf_x86_64_phone-trunk_staging-eng
    elif (echo -n $answer | grep -q -e "^[0-9][0-9]*$")
    then
        local choices=($(TARGET_BUILD_APPS= TARGET_PRODUCT= TARGET_RELEASE= TARGET_BUILD_VARIANT= get_build_var COMMON_LUNCH_CHOICES 2>/dev/null))
        if [ $answer -le ${#choices[@]} ]
        then
            # array in zsh starts from 1 instead of 0.
            if [ -n "$ZSH_VERSION" ]
            then
                selection=${choices[$(($answer))]}
            else
                selection=${choices[$(($answer-1))]}
            fi
        fi
    else
        selection=$answer
    fi

    export TARGET_BUILD_APPS=

    # This must be <product>-<release>-<variant>
    local product release variant
    # Split string on the '-' character.
    IFS="-" read -r product release variant <<< "$selection"

    if [[ -z "$product" ]] || [[ -z "$release" ]] || [[ -z "$variant" ]]
    then
        echo
        echo "Invalid lunch combo: $selection"
        echo "Valid combos must be of the form <product>-<release>-<variant>"
        return 1
    fi

    if ! check_product $product $release
    then
        # if we can't find a product, try to grab it off the LineageOS GitHub
        T=$(gettop)
        cd $T > /dev/null
        vendor/rising/build/tools/roomservice.py $product
        cd - > /dev/null
        check_product $product $release
    else
        T=$(gettop)
        cd $T > /dev/null
        vendor/rising/build/tools/roomservice.py $product true
        cd - > /dev/null
    fi

    TARGET_PRODUCT=$product \
    TARGET_BUILD_VARIANT=$variant \
    TARGET_RELEASE=$release \
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
    export TARGET_PRODUCT=$(get_build_var TARGET_PRODUCT)
    export TARGET_BUILD_VARIANT=$(get_build_var TARGET_BUILD_VARIANT)
    export TARGET_RELEASE=$release
    # Note this is the string "release", not the value of the variable.
    export TARGET_BUILD_TYPE=release

    local prebuilt_kernel=$(get_build_var TARGET_PREBUILT_KERNEL)
    if [ -z "$prebuilt_kernel" ]; then
      export INLINE_KERNEL_BUILDING=true
    else
      unset INLINE_KERNEL_BUILDING
    fi

    [[ -n "${ANDROID_QUIET_BUILD:-}" ]] || echo

    fixup_common_out_dir

    set_stuff_for_environment
    [[ -n "${ANDROID_QUIET_BUILD:-}" ]] || printconfig

    if [ $used_lunch_menu -eq 1 ]; then
      echo
      echo "Hint: next time you can simply run 'lunch $selection'"
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
        COMMON_LUNCH_CHOICES_CACHE=$(TARGET_BUILD_APPS= get_build_var COMMON_LUNCH_CHOICES)
    fi

    COMPREPLY=( $(compgen -W "${COMMON_LUNCH_CHOICES_CACHE}" -- ${cur}) )
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

# TODO: Merge into gettop as part of launching multitree
function multitree_gettop
{
    local TOPFILE=orchestrator/build/make/core/envsetup.mk
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

function adb() {
   command adb "${@}"
}

# simplified version of ps; output in the form
# <pid> <procname>
function qpid() {
    local prepend=''
    local append=''
    if [ "$1" = "--exact" ]; then
        prepend=' '
        append='$'
        shift
    elif [ "$1" = "--help" -o "$1" = "-h" ]; then
        echo "usage: qpid [[--exact] <process name|pid>"
        return 255
    fi

    local EXE="$1"
    if [ "$EXE" ] ; then
        qpid | \grep "$prepend$EXE$append"
    else
        adb shell ps \
            | tr -d '\r' \
            | sed -e 1d -e 's/^[^ ]* *\([0-9]*\).* \([^ ]*\)$/\1 \2/'
    fi
}

# syswrite - disable verity, reboot if needed, and remount image
#
# Easy way to make system.img/etc writable
function syswrite() {
  adb wait-for-device && adb root && adb wait-for-device || return 1
  if [[ $(adb disable-verity | grep -i "reboot") ]]; then
      echo "rebooting"
      adb reboot && adb wait-for-device && adb root && adb wait-for-device || return 1
  fi
  adb remount || return 1
}

# coredump_setup - enable core dumps globally for any process
#                  that has the core-file-size limit set correctly
#
# NOTE: You must call also coredump_enable for a specific process
#       if its core-file-size limit is not set already.
# NOTE: Core dumps are written to ramdisk; they will not survive a reboot!

function coredump_setup()
{
    echo "Getting root...";
    adb root;
    adb wait-for-device;

    echo "Remounting root partition read-write...";
    adb shell mount -w -o remount -t rootfs rootfs;
    sleep 1;
    adb wait-for-device;
    adb shell mkdir -p /cores;
    adb shell mount -t tmpfs tmpfs /cores;
    adb shell chmod 0777 /cores;

    echo "Granting SELinux permission to dump in /cores...";
    adb shell restorecon -R /cores;

    echo "Set core pattern.";
    adb shell 'echo /cores/core.%p > /proc/sys/kernel/core_pattern';

    echo "Done."
}

# coredump_enable - enable core dumps for the specified process
# $1 = PID of process (e.g., $(pid mediaserver))
#
# NOTE: coredump_setup must have been called as well for a core
#       dump to actually be generated.

function coredump_enable()
{
    local PID=$1;
    if [ -z "$PID" ]; then
        printf "Expecting a PID!\n";
        return;
    fi;
    echo "Setting core limit for $PID to infinite...";
    adb shell /system/bin/ulimit -P $PID -c unlimited
}

# core - send SIGV and pull the core for process
# $1 = PID of process (e.g., $(pid mediaserver))
#
# NOTE: coredump_setup must be called once per boot for core dumps to be
#       enabled globally.

function core()
{
    local PID=$1;

    if [ -z "$PID" ]; then
        printf "Expecting a PID!\n";
        return;
    fi;

    local CORENAME=core.$PID;
    local COREPATH=/cores/$CORENAME;
    local SIG=SEGV;

    coredump_enable $1;

    local done=0;
    while [ $(adb shell "[ -d /proc/$PID ] && echo -n yes") ]; do
        printf "\tSending SIG%s to %d...\n" $SIG $PID;
        adb shell kill -$SIG $PID;
        sleep 1;
    done;

    adb shell "while [ ! -f $COREPATH ] ; do echo waiting for $COREPATH to be generated; sleep 1; done"
    echo "Done: core is under $COREPATH on device.";
}

# systemstack - dump the current stack trace of all threads in the system process
# to the usual ANR traces file
function systemstack()
{
    stacks system_server
}

# Read the ELF header from /proc/$PID/exe to determine if the process is
# 64-bit.
function is64bit()
{
    local PID="$1"
    if [ "$PID" ] ; then
        if [[ "$(adb shell cat /proc/$PID/exe | xxd -l 1 -s 4 -p)" -eq "02" ]] ; then
            echo "64"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

case `uname -s` in
    Darwin)
        function sgrep()
        {
            find -E . -name .repo -prune -o -name .git -prune -o  -type f -iregex '.*\.(c|h|cc|cpp|hpp|S|java|kt|xml|sh|mk|aidl|vts|proto|rs|go)' \
                -exec grep --color -n "$@" {} +
        }

        ;;
    *)
        function sgrep()
        {
            find . -name .repo -prune -o -name .git -prune -o  -type f -iregex '.*\.\(c\|h\|cc\|cpp\|hpp\|S\|java\|kt\|xml\|sh\|mk\|aidl\|vts\|proto\|rs\|go\)' \
                -exec grep --color -n "$@" {} +
        }
        ;;
esac

function gettargetarch
{
    get_build_var TARGET_ARCH
}

function ggrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.gradle" \
        -exec grep --color -n "$@" {} +
}

function gogrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.go" \
        -exec grep --color -n "$@" {} +
}

function jgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.java" \
        -exec grep --color -n "$@" {} +
}

function rsgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.rs" \
        -exec grep --color -n "$@" {} +
}

function jsongrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.json" \
        -exec grep --color -n "$@" {} +
}

function tomlgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.toml" \
        -exec grep --color -n "$@" {} +
}

function ktgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.kt" \
        -exec grep --color -n "$@" {} +
}

function cgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) \
        -exec grep --color -n "$@" {} +
}

function resgrep()
{
    local dir
    for dir in `find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -name res -type d`; do
        find $dir -type f -name '*\.xml' -exec grep --color -n "$@" {} +
    done
}

function mangrep()
{
    find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -type f -name 'AndroidManifest.xml' \
        -exec grep --color -n "$@" {} +
}

function owngrep()
{
    find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -type f -name 'OWNERS' \
        -exec grep --color -n "$@" {} +
}

function sepgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -name sepolicy -type d \
        -exec grep --color -n -r --exclude-dir=\.git "$@" {} +
}

function rcgrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.rc*" \
        -exec grep --color -n "$@" {} +
}

function pygrep()
{
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.py" \
        -exec grep --color -n "$@" {} +
}

case `uname -s` in
    Darwin)
        function mgrep()
        {
            find -E . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o \( -iregex '.*/(Makefile|Makefile\..*|.*\.make|.*\.mak|.*\.mk|.*\.bp)' -o -regex '(.*/)?(build|soong)/.*[^/]*\.go' \) -type f \
                -exec grep --color -n "$@" {} +
        }

        function treegrep()
        {
            find -E . -name .repo -prune -o -name .git -prune -o -type f -iregex '.*\.(c|h|cpp|hpp|S|java|kt|xml)' \
                -exec grep --color -n -i "$@" {} +
        }

        ;;
    *)
        function mgrep()
        {
            find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o \( -regextype posix-egrep -iregex '(.*\/Makefile|.*\/Makefile\..*|.*\.make|.*\.mak|.*\.mk|.*\.bp)' -o -regextype posix-extended -regex '(.*/)?(build|soong)/.*[^/]*\.go' \) -type f \
                -exec grep --color -n "$@" {} +
        }

        function treegrep()
        {
            find . -name .repo -prune -o -name .git -prune -o -regextype posix-egrep -iregex '.*\.(c|h|cpp|hpp|S|java|kt|xml)' -type f \
                -exec grep --color -n -i "$@" {} +
        }

        ;;
esac

function getprebuilt
{
    get_abs_build_var ANDROID_PREBUILTS
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

function getbugreports()
{
    local reports=(`adb shell ls /sdcard/bugreports | tr -d '\r'`)

    if [ ! "$reports" ]; then
        echo "Could not locate any bugreports."
        return
    fi

    local report
    for report in ${reports[@]}
    do
        echo "/sdcard/bugreports/${report}"
        adb pull /sdcard/bugreports/${report} ${report}
        gunzip ${report}
    done
}

function getsdcardpath()
{
    adb ${adbOptions} shell echo -n \$\{EXTERNAL_STORAGE\}
}

function getscreenshotpath()
{
    echo "$(getsdcardpath)/Pictures/Screenshots"
}

function getlastscreenshot()
{
    local screenshot_path=$(getscreenshotpath)
    local screenshot=`adb ${adbOptions} ls ${screenshot_path} | grep Screenshot_[0-9-]*.*\.png | sort -rk 3 | cut -d " " -f 4 | head -n 1`
    if [ "$screenshot" = "" ]; then
        echo "No screenshots found."
        return
    fi
    echo "${screenshot}"
    adb ${adbOptions} pull ${screenshot_path}/${screenshot}
}

function startviewserver()
{
    local port=4939
    if [ $# -gt 0 ]; then
            port=$1
    fi
    adb shell service call window 1 i32 $port
}

function stopviewserver()
{
    adb shell service call window 2
}

function isviewserverstarted()
{
    adb shell service call window 3
}

function key_home()
{
    adb shell input keyevent 3
}

function key_back()
{
    adb shell input keyevent 4
}

function key_menu()
{
    adb shell input keyevent 82
}

function smoketest()
{
    if [ ! "$ANDROID_PRODUCT_OUT" ]; then
        echo "Couldn't locate output files.  Try running 'lunch' first." >&2
        return
    fi
    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi

    (\cd "$T" && mmm tests/SmokeTest) &&
      adb uninstall com.android.smoketest > /dev/null &&
      adb uninstall com.android.smoketest.tests > /dev/null &&
      adb install $ANDROID_PRODUCT_OUT/data/app/SmokeTestApp.apk &&
      adb install $ANDROID_PRODUCT_OUT/data/app/SmokeTest.apk &&
      adb shell am instrument -w com.android.smoketest.tests/android.test.InstrumentationTestRunner
}

# simple shortcut to the runtest command
function runtest()
{
    local T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    ("$T"/development/testrunner/runtest.py $@)
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

# Update module-info.json in out.
function refreshmod() {
    if [ ! "$ANDROID_PRODUCT_OUT" ]; then
        echo "No ANDROID_PRODUCT_OUT. Try running 'lunch' first." >&2
        return 1
    fi

    echo "Refreshing modules (building module-info.json). Log at $ANDROID_PRODUCT_OUT/module-info.json.build.log." >&2

    # for the output of the next command
    mkdir -p $ANDROID_PRODUCT_OUT || return 1

    # Note, can't use absolute path because of the way make works.
    m $(get_build_var PRODUCT_OUT)/module-info.json \
        > $ANDROID_PRODUCT_OUT/module-info.json.build.log 2>&1
}

# Verifies that module-info.txt exists, returning nonzero if it doesn't.
function verifymodinfo() {
    if [ ! "$ANDROID_PRODUCT_OUT" ]; then
        if [ "$QUIET_VERIFYMODINFO" != "true" ] ; then
            echo "No ANDROID_PRODUCT_OUT. Try running 'lunch' first." >&2
        fi
        return 1
    fi

    if [ ! -f "$ANDROID_PRODUCT_OUT/module-info.json" ]; then
        if [ "$QUIET_VERIFYMODINFO" != "true" ] ; then
            echo "Could not find module-info.json. Please run 'refreshmod' first." >&2
        fi
        return 1
    fi
}

# List all modules for the current device, as cached in all_modules.txt. If any build change is
# made and it should be reflected in the output, you should run `m nothing` first.
function allmod() {
    cat $ANDROID_PRODUCT_OUT/all_modules.txt 2>/dev/null
}

# Return the Bazel label of a Soong module if it is converted with bp2build.
function bmod()
(
    if [ $# -eq 0 ]; then
        echo "usage: bmod <module 1> <module 2> ... <module n>" >&2
        return 1
    fi

    # We could run bp2build here, but it might trigger bp2build invalidation
    # when used with `b` (e.g. --run_soong_tests) and/or add unnecessary waiting
    # time overhead.
    #
    # For a snappy result, use the latest generated version in soong_injection,
    # and ask users to run m bp2build if it doesn't exist.
    converted_json="$(get_abs_build_var OUT_DIR)/soong/soong_injection/metrics/converted_modules_path_map.json"

    if [ ! -f ${converted_json} ]; then
      echo "bp2build files not found. Have you ran 'm bp2build'?" >&2
      return 1
    fi

    modules=()
    for m in "$@"; do
        modules+=("\"$m\",")
    done
    local res=$(python3 -c "import json
modules = [${modules[*]}]
converted_json='$converted_json'
bp2build_converted_map = json.load(open(converted_json))
for module in modules:
    if module not in bp2build_converted_map:
        print(module + ' is not converted to Bazel.')
    else:
        print(bp2build_converted_map[module] + ':' + module)")

    echo "${res}"
    unconverted_count=$(echo "${res}" | grep -c "not converted to Bazel")
    if [[ ${unconverted_count} -ne 0 ]]; then
        return 1
    fi
)

# Get the path of a specific module in the android tree, as cached in module-info.json.
# If any build change is made, and it should be reflected in the output, you should run
# 'refreshmod' first.  Note: This is the inverse of dirmods.
function pathmod() {
    if [[ $# -ne 1 ]]; then
        echo "usage: pathmod <module>" >&2
        return 1
    fi

    verifymodinfo || return 1

    local relpath=$(python3 -c "import json, os
module = '$1'
module_info = json.load(open('$ANDROID_PRODUCT_OUT/module-info.json'))
if module not in module_info:
    exit(1)
print(module_info[module]['path'][0])" 2>/dev/null)

    if [ -z "$relpath" ]; then
        echo "Could not find module '$1' (try 'refreshmod' if there have been build changes?)." >&2
        return 1
    else
        echo "$ANDROID_BUILD_TOP/$relpath"
    fi
}

# Get the path of a specific module in the android tree, as cached in module-info.json.
# If any build change is made, and it should be reflected in the output, you should run
# 'refreshmod' first.  Note: This is the inverse of pathmod.
function dirmods() {
    if [[ $# -ne 1 ]]; then
        echo "usage: dirmods <path>" >&2
        return 1
    fi

    verifymodinfo || return 1

    python3 -c "import json, os
dir = '$1'
while dir.endswith('/'):
    dir = dir[:-1]
prefix = dir + '/'
module_info = json.load(open('$ANDROID_PRODUCT_OUT/module-info.json'))
results = set()
for m in module_info.values():
    for path in m.get(u'path', []):
        if path == dir or path.startswith(prefix):
            name = m.get(u'module_name')
            if name:
                results.add(name)
for name in sorted(results):
    print(name)
"
}


# Go to a specific module in the android tree, as cached in module-info.json. If any build change
# is made, and it should be reflected in the output, you should run 'refreshmod' first.
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

# Gets the list of a module's installed outputs, as cached in module-info.json.
# If any build change is made, and it should be reflected in the output, you should run 'refreshmod' first.
function outmod() {
    if [[ $# -ne 1 ]]; then
        echo "usage: outmod <module>" >&2
        return 1
    fi

    verifymodinfo || return 1

    local relpath
    relpath=$(python3 -c "import json, os
module = '$1'
module_info = json.load(open('$ANDROID_PRODUCT_OUT/module-info.json'))
if module not in module_info:
    exit(1)
for output in module_info[module]['installed']:
    print(os.path.join('$ANDROID_BUILD_TOP', output))" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "Could not find module '$1' (try 'refreshmod' if there have been build changes?)" >&2
        return 1
    elif [ ! -z "$relpath" ]; then
        echo "$relpath"
    fi
}

# adb install a module's apk, as cached in module-info.json. If any build change
# is made, and it should be reflected in the output, you should run 'refreshmod' first.
# Usage: installmod [adb install arguments] <module>
# For example: installmod -r Dialer -> adb install -r /path/to/Dialer.apk
function installmod() {
    if [[ $# -eq 0 ]]; then
        echo "usage: installmod [adb install arguments] <module>" >&2
        echo "" >&2
        echo "Only flags to be passed after the \"install\" in adb install are supported," >&2
        echo "with the exception of -s. If -s is passed it will be placed before the \"install\"." >&2
        echo "-s must be the first flag passed if it exists." >&2
        return 1
    fi

    local _path
    _path=$(outmod ${@:$#:1})
    if [ $? -ne 0 ]; then
        return 1
    fi

    _path=$(echo "$_path" | grep -E \\.apk$ | head -n 1)
    if [ -z "$_path" ]; then
        echo "Module '$1' does not produce a file ending with .apk (try 'refreshmod' if there have been build changes?)" >&2
        return 1
    fi
    local serial_device=""
    if [[ "$1" == "-s" ]]; then
        if [[ $# -le 2 ]]; then
            echo "-s requires an argument" >&2
            return 1
        fi
        serial_device="-s $2"
        shift 2
    fi
    local length=$(( $# - 1 ))
    echo adb $serial_device install ${@:1:$length} $_path
    adb $serial_device install ${@:1:$length} $_path
}

function _complete_android_module_names() {
    local word=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=( $(allmod | grep -E "^$word") )
}

# Print colored exit condition
function pez {
    "$@"
    local retval=$?
    if [ $retval -ne 0 ]
    then
        echo $'\E'"[0;31mFAILURE\e[00m"
    else
        echo $'\E'"[0;32mSUCCESS\e[00m"
    fi
    return $retval
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

function _wrap_build()
{
    if [[ "${ANDROID_QUIET_BUILD:-}" == true ]]; then
      "$@"
      return $?
    fi
    local start_time=$(date +"%s")
    "$@"
    local ret=$?
    local end_time=$(date +"%s")
    local tdiff=$(($end_time-$start_time))
    local hours=$(($tdiff / 3600 ))
    local mins=$((($tdiff % 3600) / 60))
    local secs=$(($tdiff % 60))
    local ncolors=$(tput colors 2>/dev/null)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        color_failed=$'\E'"[0;31m"
        color_success=$'\E'"[0;32m"
        color_warning=$'\E'"[0;33m"
        color_reset=$'\E'"[00m"
    else
        color_failed=""
        color_success=""
        color_reset=""
    fi

    echo
    if [ $ret -eq 0 ] ; then
        echo -n "${color_success}#### build completed successfully "
    else
        echo -n "${color_failed}#### failed to build some targets "
    fi
    if [ $hours -gt 0 ] ; then
        printf "(%02g:%02g:%02g (hh:mm:ss))" $hours $mins $secs
    elif [ $mins -gt 0 ] ; then
        printf "(%02g:%02g (mm:ss))" $mins $secs
    elif [ $secs -gt 0 ] ; then
        printf "(%s seconds)" $secs
    fi
    echo " ####${color_reset}"
    echo
    return $ret
}

function _trigger_build()
(
    local -r bc="$1"; shift
    local T=$(gettop)
    if [ -n "$T" ]; then
      _wrap_build "$T/build/soong/soong_ui.bash" --build-mode --${bc} --dir="$(pwd)" "$@"
    else
      >&2 echo "Couldn't locate the top of the tree. Try setting TOP."
      return 1
    fi
    local ret=$?
    if [[ ret -eq 0 &&  -z "${ANDROID_QUIET_BUILD:-}" && -n "${ANDROID_BUILD_BANNER}" ]]; then
      echo "${ANDROID_BUILD_BANNER}"
    fi
    return $ret
)

function m()
(
    _trigger_build "all-modules" "$@"
)

function mm()
(
    _trigger_build "modules-in-a-dir-no-deps" "$@"
)

function mmm()
(
    _trigger_build "modules-in-dirs-no-deps" "$@"
)

function mma()
(
    _trigger_build "modules-in-a-dir" "$@"
)

function mmma()
(
    _trigger_build "modules-in-dirs" "$@"
)

function make()
{
    _wrap_build $(get_make_command "$@") "$@"
}

function _multitree_lunch_error()
{
      >&2 echo "Couldn't locate the top of the tree. Please run \'source build/envsetup.sh\' and multitree_lunch from the root of your workspace."
}

function multitree_build()
{
    local T=$(multitree_gettop)
    if [ -n "$T" ]; then
      "$T/orchestrator/build/orchestrator/core/orchestrator.py" "$@"
    else
      _multitree_lunch_error
      return 1
    fi
}

function provision()
{
    if [ ! "$ANDROID_PRODUCT_OUT" ]; then
        echo "Couldn't locate output files.  Try running 'lunch' first." >&2
        return 1
    fi
    if [ ! -e "$ANDROID_PRODUCT_OUT/provision-device" ]; then
        echo "There is no provisioning script for the device." >&2
        return 1
    fi

    # Check if user really wants to do this.
    if [ "$1" = "--no-confirmation" ]; then
        shift 1
    else
        echo "This action will reflash your device."
        echo ""
        echo "ALL DATA ON THE DEVICE WILL BE IRREVOCABLY ERASED."
        echo ""
        echo -n "Are you sure you want to do this (yes/no)? "
        read
        if [[ "${REPLY}" != "yes" ]] ; then
            echo "Not taking any action. Exiting." >&2
            return 1
        fi
    fi
    "$ANDROID_PRODUCT_OUT/provision-device" "$@"
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

    if [[ "${PWD}" == /google/cog/* ]]; then
        f="build/make/cogsetup.sh"
        echo "including $f"; . "$T/$f"
    fi
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
    OUT_DIR="$(get_abs_build_var OUT_DIR)"
    if [[ "$1" == "--regenerate" ]]; then
      shift 1
      NINJA_ARGS="-t commands $@" m
    else
      (cd $T && prebuilts/build-tools/$PREBUILT_NAME/bin/ninja \
          -f $OUT_DIR/combined-${TARGET_PRODUCT}.ninja \
          -t commands "$@")
    fi
}

function avbtool() {
    if [[ ! -f "$ANDROID_SOONG_HOST_OUT"/bin/avbtool ]]; then
        m avbtool
    fi
    "$ANDROID_SOONG_HOST_OUT"/bin/avbtool $@
}

function overrideflags() {
    local T="$(gettop)"
    (\cd "${T}" && build/make/tools/overrideflags.sh "$@")
}

function aninja() {
    local T="$(gettop)"
    (\cd "${T}" && prebuilts/build-tools/linux-x86/bin/ninja -f out/combined-${TARGET_PRODUCT}.ninja "$@")
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
            CURRENT_CCACHE_SIZE=$(du -sh "$CCACHE_DIR" 2>/dev/null | cut -f1)
            if [ -n "$CURRENT_CCACHE_SIZE" ]; then
                echo "Current ccache size is: $CURRENT_CCACHE_SIZE" >&2
            else
                echo "No cached files in ccache." >&2
            fi
        else
            echo "Error: ccache not found. Please install ccache." >&2
        fi
    fi
}

function riseupload() {
    read -p "Enter your SourceForge username: " sf_username
    target_device="$(get_build_var TARGET_DEVICE)"
    package_type="$(get_build_var RISING_PACKAGE_TYPE)"
    rising_version="$(get_build_var RISING_VERSION)"
    rising_version="${rising_version%.*}.x"
    product_out="out/target/product/$target_device/"
    source_file="$(find "$product_out" -maxdepth 1 -type f -name 'RisingOS-*.zip' -print -quit)"
    
    if [ -z "$source_file" ]; then
        echo "Error: Could not find RisingOS zip file in $product_out"
        return 1
    fi
    
    filename="$(basename "$source_file" .zip)"
    destination="${sf_username}@frs.sourceforge.net:/home/frs/project/risingos-official/$rising_version/$package_type/$target_device/"
    rsync -e ssh "$source_file" "$destination"
}

function riseup() {
    local device="$1"
    local build_type="$2"
    source ${ANDROID_BUILD_TOP}/vendor/rising/vars/aosp_target_release

    if [ -z "$device" ]; then
        if [[ -n "$TARGET_PRODUCT" ]]; then
            device=$(echo "$TARGET_PRODUCT" | sed -E 's/lineage_([^_]+).*/\1/')
            echo "No argument found for device, using TARGET_PRODUCT as device: $device"
        else
            echo "Correct usage: riseup <device_codename> [build_type]"
            echo "Available build types: user, userdebug, eng"
            return 1
        fi
    fi

    if [ -z "$build_type" ]; then
        build_type="userdebug"
    fi

    case "$build_type" in
        user|userdebug|eng)
        lunch lineage_"$device"-"$aosp_target_release"-"$build_type"
        ;;
        *)
        echo "Invalid build type."
        echo "Available build types are: user, userdebug & eng"
        ;;
    esac
}

function ascend() {
    if [[ -z "$TARGET_PRODUCT" ]]; then
        echo "Error: No device target set. Please use 'riseup' or 'lunch' to set the target device."
        return 1
    fi

    echo "ascend is deprecated. Please use rise instead."
    echo "Usage: rise [b|fb]"
    echo "   b   - Build bacon"
    echo "   fb  - Fastboot update"

    case "$1" in
        "fastboot")
            rise fb
            ;;
        *)
            rise b
            ;;
    esac
}

function rise() {
    if [[ "$1" == "help" ]]; then
        echo "Usage: rise [b|fb|sb] [-j<num_cores>]"
        echo "   b   - Build bacon"
        echo "   fb  - Fastboot update"
        echo "   sb  - Signed Build"
        echo "   -j<num_cores>  - Specify the number of cores to use for the build"
        return 0
    fi

    if [[ -z "$TARGET_PRODUCT" ]]; then
        echo "Error: No device target set. Please use 'riseup' or 'lunch' to set the target device."
        return 1
    fi

    m installclean

    local jCount=""
    local cmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j*)
                jCount="$1"
                ;;
            b|fb|sb)
                cmd="$1"
                ;;
            *)
                echo "Error: Invalid argument mode. Please use 'b', 'fb', 'sb', 'help', or a job count flag like '-j<number>'."
                echo "Usage: rise [b|fb|sb] [-j<num_cores>]"
                return 1
                ;;
        esac
        shift
    done

    case "$cmd" in
        sb)
            if [[ ! -f "$ANDROID_KEY_PATH/releasekey.pk8" || ! -f "$ANDROID_KEY_PATH/releasekey.x509.pem" ]]; then
                echo "Keys not found. Generating keys..."
                genkeys
            fi
            sign_build ${jCount:--j$(nproc --all)}
            ;;
        b)
            m bacon ${jCount:--j$(nproc --all)}
            ;;
        fb)
            m updatepackage ${jCount:--j$(nproc --all)}
            ;;
        "")
            m ${jCount:--j$(nproc --all)}
            ;;
    esac
}

function add_remote() {
    local remote_name="$1"
    local remote_url="$2"
    local manifest_path="android/snippets/rising.xml"
    local exclusion_list=("android" "vendor/risingOTA" "packages/apps/FaceUnlock" "vendor/gms")
    if [[ -z "$remote_name" || -z "$remote_url" ]]; then
        echo "Usage: add_remote <remote_name> <remote_url>"
        return 1
    fi
    echo "Adding remote '$remote_name' with URL '$remote_url' to repositories in manifest: $manifest_path"
    while IFS= read -r line; do
        if [[ $line == *"<project "* && $line == *"remote="* ]]; then
            local repo_path=$(echo "$line" | grep -oP 'path="\K[^"]+')
            local manifest_entry=$(echo "$line" | grep -oP 'name="\K[^"]+')
            local existing_remote=$(echo "$line" | grep -oP 'remote="\K[^"]+')
            if [[ ! " ${exclusion_list[@]} " =~ " $repo_path " ]]; then
                if [[ "$existing_remote" != "$remote_name" ]]; then
                    local new_url="$remote_url/$manifest_entry"
                    git -C "$repo_path" remote add "$remote_name" "$new_url"
                    echo "Added remote '$remote_name' with URL '$new_url' to repository: $repo_path"
                else
                    echo "Remote '$remote_name' already exists in repository: $repo_path"
                fi
            else
                echo "Repository '$repo_path' is in the exclusion list. Skipping..."
            fi
        fi
    done < "$manifest_path"
}

function remove_remote() {
    local remote_name="$1"
    local manifest_path="android/snippets/rising.xml"
    if [[ -z "$remote_name" ]]; then
        echo "Usage: remove_remote <remote_name>"
        return 1
    fi
    echo "Removing remote '$remote_name' from repositories in manifest: $manifest_path"
    while IFS= read -r line; do
        if [[ $line == *"<project "* && $line == *"remote="* ]]; then
            local repo_path=$(echo "$line" | grep -oP 'path="\K[^"]+')
            if git -C "$repo_path" remote | grep -q "^$remote_name$"; then
                git -C "$repo_path" remote remove "$remote_name"
                echo "Removed remote '$remote_name' from repository: $repo_path"
            else
                echo "Remote '$remote_name' doesn't exist in repository: $repo_path"
            fi
        fi
    done < "$manifest_path"
}

function force_push() {
    local remote_name="$1"
    local remote_branch="$2"
    local manifest_path="android/snippets/rising.xml"
    local exclusion_list=("android" "vendor/risingOTA" "packages/apps/FaceUnlock" "vendor/gms")
    echo "Pushing changes to remote '$remote_name' in repositories from manifest: $manifest_path"
    while IFS= read -r line; do
        if [[ $line == *"<project "* && $line == *"remote="* ]]; then
            local repo_path=$(echo "$line" | grep -oP 'path="\K[^"]+')
            local remote=$(echo "$line" | grep -oP 'remote="\K[^"]+')
            local branch=$(echo "$line" | grep -oP 'revision="\K[^"]+')
            if [[ ! "$remote" =~ ^(staging|rising)$ ]]; then
                echo "Invalid remote '$remote' for repository '$repo_path'. Skipping..."
                continue
            fi
            if [[ " ${exclusion_list[@]} " =~ " $repo_path " ]]; then
                echo "Repository '$repo_path' is in the exclusion list. Skipping..."
                continue
            fi
            if [[ -n "$remote_branch" ]]; then
                branch="$remote_branch"
            fi
            echo "Pushing changes from branch '$branch' to remote '$remote_name' in repository: $repo_path"
            if ! git -C "$repo_path" show-ref --quiet refs/heads/"$branch"; then
                git -C "$repo_path" checkout -b "$branch" &> /dev/null
            fi
            git -C "$repo_path" push -f "$remote_name" "$branch" 2>&1 | grep -v "already exists"
        fi
    done < "$manifest_path"
}

function setupGlobalThinLto() {
    local option="$1"
    if [[ "$option" == "true" ]]; then
        echo "Building with ThinLTO."
        export GLOBAL_THINLTO=true
        export USE_THINLTO_CACHE=true
    elif [[ "$option" == "false" ]]; then
        echo "Disabling ThinLTO."
        export GLOBAL_THINLTO=false
        export USE_THINLTO_CACHE=false
    else
        echo "Invalid option. Please provide either 'true' or 'false'."
    fi
}

# usage:
# pushRepo 190000 main fourteen
function pushRepo() {
    total_heads=$1
    remote=$2
    branch=$3
    repo_path=$4
    while [ $total_heads -gt 0 ]
    do
        commit_offset=$(( total_heads - 10000 ))
        if [ $commit_offset -lt 0 ]; then
            commit_offset=0
        fi
        git -C "$repo_path" push -u $remote HEAD~$commit_offset:refs/heads/$branch

        total_heads=$(( total_heads - 10000 ))
    done
}

function remove_broken_build_tools() {
    rm -rf prebuilts/build-tools/path/*/date
    rm -rf prebuilts/build-tools/path/*/tar
}

function genkeys() {
    unset key_password
    local git_email=$(git config --global user.email)
    if [ -z "$git_email" ]; then
        echo "Git email address is not set. Please set it using 'git config --global user.email'."
        exit 1
    fi
    read -p "Enter your email address (leave empty to use Git email: $git_email): " email
    email=${email:-$git_email}
    read -sp "Enter password (leave empty for no password): " key_password
    echo ""
    generate_keys() {
        local email="$1"
        local subject="/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=$email"
        local key_names=("recovery" "nfc" "bluetooth" "media" "networkstack" "platform" "releasekey" "sdk_sandbox" "shared" "testcert" "testkey" "verity")
        mkdir -p "$ANDROID_KEY_PATH"
        for key_name in "${key_names[@]}"; do
            if [ -f "$ANDROID_KEY_PATH/$key_name.pk8" ] || [ -f "$ANDROID_KEY_PATH/$key_name.x509.pem" ]; then
                echo "Deleting existing files for $key_name..."
                rm -f "$ANDROID_KEY_PATH/$key_name.pk8" "$ANDROID_KEY_PATH/$key_name.x509.pem"
            fi
            if [ -n "$key_password" ]; then
                echo "Executing make_key for $key_name with provided password..."
                echo "$key_password" | ./development/tools/make_key "$ANDROID_KEY_PATH/$key_name" "$subject"
            else
                echo "Executing make_key for $key_name without password..."
                echo "" | ./development/tools/make_key "$ANDROID_KEY_PATH/$key_name" "$subject"
            fi
        done
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
    }
    echo "Generating keys using $email..."
    generate_keys "$email"

    echo "PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey" > vendor/lineage-priv/keys/keys.mk
    echo "PRODUCT_EXTRA_RECOVERY_KEYS := vendor/lineage-priv/keys/recovery" >> vendor/lineage-priv/keys/keys.mk

    bazel_build_content="filegroup(
    name = \"android_certificate_directory\",
    srcs = glob([
        \"*.pk8\",
        \"*.pem\",
    ]),
    visibility = [\"//visibility:public\"],
)"
    echo "$bazel_build_content" > vendor/lineage-priv/keys/BUILD.bazel
}

function remove_keys() {
    local key_mk="vendor/lineage-priv/keys/keys.mk"
    local build_bazel="vendor/lineage-priv/keys/BUILD.bazel"

    if [ -f "$key_mk" ]; then
        echo "Removing $key_mk..."
        rm -f "$key_mk"
    else
        echo "$key_mk does not exist."
    fi

    if [ -f "$build_bazel" ]; then
        echo "Removing $build_bazel..."
        rm -f "$build_bazel"
    else
        echo "$build_bazel does not exist."
    fi
}

function sign_build() {
    local rising_build_version="$(get_build_var RISING_BUILD_VERSION)"
    local rising_version="$(get_build_var RISING_VERSION)"
    local rising_codename="$(get_build_var RISING_CODENAME)"
    local rising_package_type="$(get_build_var RISING_PACKAGE_TYPE)"
    local rising_release_type="$(get_build_var RISING_RELEASE_TYPE)"
    local target_device="$(get_build_var TARGET_DEVICE)"
    local jobCount="$1"
    local key_path="$ANDROID_BUILD_TOP/vendor/lineage-priv/signing/keys"
    if ! m target-files-package otatools "$jobCount"; then
        echo "Build failed, skipping signing of the package."
        return 1
    fi
    sign_target_files
    genSignedOta
    local source_file="$OUT/signed-ota_update.zip"
    local target_file="$OUT/RisingOS-$rising_build_version-ota-signed.zip"
    if [[ -e "$source_file" ]]; then
        mv "$source_file" "$target_file"
        echo "Renamed $source_file to $target_file"
    else
        echo "File $source_file does not exist."
        return 1
    fi
    echo "Creating RisingOS JSON OTA..."
    $ANDROID_BUILD_TOP/vendor/rising/build/tools/createjson.sh "$target_device" "$OUT" "RisingOS-$rising_build_version-ota-signed.zip" "$rising_version" "$rising_codename" "$rising_package_type" "$rising_release_type"
    cp -f "$OUT/$target_device.json" "vendor/risingOTA/$target_device.json"
    echo "RisingOS JSON OTA created and copied."
}

function sign_target_files() {
    croot
    sign_target_files_apks -o -d $ANDROID_KEY_PATH \
        --extra_apks AdServicesApk.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks HalfSheetUX.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks OsuLogin.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks SafetyCenterResources.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks ServiceConnectivityResources.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks ServiceUwbResources.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks ServiceWifiResources.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks WifiDialog.apk=$ANDROID_KEY_PATH/releasekey \
        --extra_apks com.android.adbd.apex=$ANDROID_KEY_PATH/com.android.adbd \
        --extra_apks com.android.adservices.apex=$ANDROID_KEY_PATH/com.android.adservices \
        --extra_apks com.android.adservices.api.apex=$ANDROID_KEY_PATH/com.android.adservices.api \
        --extra_apks com.android.appsearch.apex=$ANDROID_KEY_PATH/com.android.appsearch \
        --extra_apks com.android.art.apex=$ANDROID_KEY_PATH/com.android.art \
        --extra_apks com.android.bluetooth.apex=$ANDROID_KEY_PATH/com.android.bluetooth \
        --extra_apks com.android.btservices.apex=$ANDROID_KEY_PATH/com.android.btservices \
        --extra_apks com.android.cellbroadcast.apex=$ANDROID_KEY_PATH/com.android.cellbroadcast \
        --extra_apks com.android.compos.apex=$ANDROID_KEY_PATH/com.android.compos \
        --extra_apks com.android.configinfrastructure.apex=$ANDROID_KEY_PATH/com.android.configinfrastructure \
        --extra_apks com.android.connectivity.resources.apex=$ANDROID_KEY_PATH/com.android.connectivity.resources \
        --extra_apks com.android.conscrypt.apex=$ANDROID_KEY_PATH/com.android.conscrypt \
        --extra_apks com.android.devicelock.apex=$ANDROID_KEY_PATH/com.android.devicelock \
        --extra_apks com.android.extservices.apex=$ANDROID_KEY_PATH/com.android.extservices \
        --extra_apks com.android.graphics.pdf.apex=$ANDROID_KEY_PATH/com.android.graphics.pdf \
        --extra_apks com.android.hardware.biometrics.face.virtual.apex=$ANDROID_KEY_PATH/com.android.hardware.biometrics.face.virtual \
        --extra_apks com.android.hardware.biometrics.fingerprint.virtual.apex=$ANDROID_KEY_PATH/com.android.hardware.biometrics.fingerprint.virtual \
        --extra_apks com.android.hardware.boot.apex=$ANDROID_KEY_PATH/com.android.hardware.boot \
        --extra_apks com.android.hardware.cas.apex=$ANDROID_KEY_PATH/com.android.hardware.cas \
        --extra_apks com.android.hardware.wifi.apex=$ANDROID_KEY_PATH/com.android.hardware.wifi \
        --extra_apks com.android.healthfitness.apex=$ANDROID_KEY_PATH/com.android.healthfitness \
        --extra_apks com.android.hotspot2.osulogin.apex=$ANDROID_KEY_PATH/com.android.hotspot2.osulogin \
        --extra_apks com.android.i18n.apex=$ANDROID_KEY_PATH/com.android.i18n \
        --extra_apks com.android.ipsec.apex=$ANDROID_KEY_PATH/com.android.ipsec \
        --extra_apks com.android.media.apex=$ANDROID_KEY_PATH/com.android.media \
        --extra_apks com.android.media.swcodec.apex=$ANDROID_KEY_PATH/com.android.media.swcodec \
        --extra_apks com.android.mediaprovider.apex=$ANDROID_KEY_PATH/com.android.mediaprovider \
        --extra_apks com.android.nearby.halfsheet.apex=$ANDROID_KEY_PATH/com.android.nearby.halfsheet \
        --extra_apks com.android.networkstack.tethering.apex=$ANDROID_KEY_PATH/com.android.networkstack.tethering \
        --extra_apks com.android.neuralnetworks.apex=$ANDROID_KEY_PATH/com.android.neuralnetworks \
        --extra_apks com.android.ondevicepersonalization.apex=$ANDROID_KEY_PATH/com.android.ondevicepersonalization \
        --extra_apks com.android.os.statsd.apex=$ANDROID_KEY_PATH/com.android.os.statsd \
        --extra_apks com.android.permission.apex=$ANDROID_KEY_PATH/com.android.permission \
        --extra_apks com.android.resolv.apex=$ANDROID_KEY_PATH/com.android.resolv \
        --extra_apks com.android.rkpd.apex=$ANDROID_KEY_PATH/com.android.rkpd \
        --extra_apks com.android.runtime.apex=$ANDROID_KEY_PATH/com.android.runtime \
        --extra_apks com.android.safetycenter.resources.apex=$ANDROID_KEY_PATH/com.android.safetycenter.resources \
        --extra_apks com.android.scheduling.apex=$ANDROID_KEY_PATH/com.android.scheduling \
        --extra_apks com.android.sdkext.apex=$ANDROID_KEY_PATH/com.android.sdkext \
        --extra_apks com.android.support.apexer.apex=$ANDROID_KEY_PATH/com.android.support.apexer \
        --extra_apks com.android.telephony.apex=$ANDROID_KEY_PATH/com.android.telephony \
        --extra_apks com.android.telephonymodules.apex=$ANDROID_KEY_PATH/com.android.telephonymodules \
        --extra_apks com.android.tethering.apex=$ANDROID_KEY_PATH/com.android.tethering \
        --extra_apks com.android.tzdata.apex=$ANDROID_KEY_PATH/com.android.tzdata \
        --extra_apks com.android.uwb.apex=$ANDROID_KEY_PATH/com.android.uwb \
        --extra_apks com.android.uwb.resources.apex=$ANDROID_KEY_PATH/com.android.uwb.resources \
        --extra_apks com.android.virt.apex=$ANDROID_KEY_PATH/com.android.virt \
        --extra_apks com.android.vndk.current.apex=$ANDROID_KEY_PATH/com.android.vndk.current \
        --extra_apks com.android.vndk.current.on_vendor.apex=$ANDROID_KEY_PATH/com.android.vndk.current.on_vendor \
        --extra_apks com.android.wifi.apex=$ANDROID_KEY_PATH/com.android.wifi \
        --extra_apks com.android.wifi.dialog.apex=$ANDROID_KEY_PATH/com.android.wifi.dialog \
        --extra_apks com.android.wifi.resources.apex=$ANDROID_KEY_PATH/com.android.wifi.resources \
        --extra_apks com.google.pixel.camera.hal.apex=$ANDROID_KEY_PATH/com.google.pixel.camera.hal \
        --extra_apks com.google.pixel.vibrator.hal.apex=$ANDROID_KEY_PATH/com.google.pixel.vibrator.hal \
        --extra_apks com.qorvo.uwb.apex=$ANDROID_KEY_PATH/com.qorvo.uwb \
        --extra_apex_payload_key com.android.adbd.apex=$ANDROID_KEY_PATH/com.android.adbd.pem \
        --extra_apex_payload_key com.android.adservices.apex=$ANDROID_KEY_PATH/com.android.adservices.pem \
        --extra_apex_payload_key com.android.adservices.api.apex=$ANDROID_KEY_PATH/com.android.adservices.api.pem \
        --extra_apex_payload_key com.android.appsearch.apex=$ANDROID_KEY_PATH/com.android.appsearch.pem \
        --extra_apex_payload_key com.android.art.apex=$ANDROID_KEY_PATH/com.android.art.pem \
        --extra_apex_payload_key com.android.bluetooth.apex=$ANDROID_KEY_PATH/com.android.bluetooth.pem \
        --extra_apex_payload_key com.android.btservices.apex=$ANDROID_KEY_PATH/com.android.btservices.pem \
        --extra_apex_payload_key com.android.cellbroadcast.apex=$ANDROID_KEY_PATH/com.android.cellbroadcast.pem \
        --extra_apex_payload_key com.android.compos.apex=$ANDROID_KEY_PATH/com.android.compos.pem \
        --extra_apex_payload_key com.android.configinfrastructure.apex=$ANDROID_KEY_PATH/com.android.configinfrastructure.pem \
        --extra_apex_payload_key com.android.connectivity.resources.apex=$ANDROID_KEY_PATH/com.android.connectivity.resources.pem \
        --extra_apex_payload_key com.android.conscrypt.apex=$ANDROID_KEY_PATH/com.android.conscrypt.pem \
        --extra_apex_payload_key com.android.devicelock.apex=$ANDROID_KEY_PATH/com.android.devicelock.pem \
        --extra_apex_payload_key com.android.extservices.apex=$ANDROID_KEY_PATH/com.android.extservices.pem \
        --extra_apex_payload_key com.android.graphics.pdf.apex=$ANDROID_KEY_PATH/com.android.graphics.pdf.pem \
        --extra_apex_payload_key com.android.hardware.biometrics.face.virtual.apex=$ANDROID_KEY_PATH/com.android.hardware.biometrics.face.virtual.pem \
        --extra_apex_payload_key com.android.hardware.biometrics.fingerprint.virtual.apex=$ANDROID_KEY_PATH/com.android.hardware.biometrics.fingerprint.virtual.pem \
        --extra_apex_payload_key com.android.hardware.boot.apex=$ANDROID_KEY_PATH/com.android.hardware.boot.pem \
        --extra_apex_payload_key com.android.hardware.cas.apex=$ANDROID_KEY_PATH/com.android.hardware.cas.pem \
        --extra_apex_payload_key com.android.hardware.wifi.apex=$ANDROID_KEY_PATH/com.android.hardware.wifi.pem \
        --extra_apex_payload_key com.android.healthfitness.apex=$ANDROID_KEY_PATH/com.android.healthfitness.pem \
        --extra_apex_payload_key com.android.hotspot2.osulogin.apex=$ANDROID_KEY_PATH/com.android.hotspot2.osulogin.pem \
        --extra_apex_payload_key com.android.i18n.apex=$ANDROID_KEY_PATH/com.android.i18n.pem \
        --extra_apex_payload_key com.android.ipsec.apex=$ANDROID_KEY_PATH/com.android.ipsec.pem \
        --extra_apex_payload_key com.android.media.apex=$ANDROID_KEY_PATH/com.android.media.pem \
        --extra_apex_payload_key com.android.media.swcodec.apex=$ANDROID_KEY_PATH/com.android.media.swcodec.pem \
        --extra_apex_payload_key com.android.mediaprovider.apex=$ANDROID_KEY_PATH/com.android.mediaprovider.pem \
        --extra_apex_payload_key com.android.nearby.halfsheet.apex=$ANDROID_KEY_PATH/com.android.nearby.halfsheet.pem \
        --extra_apex_payload_key com.android.networkstack.tethering.apex=$ANDROID_KEY_PATH/com.android.networkstack.tethering.pem \
        --extra_apex_payload_key com.android.neuralnetworks.apex=$ANDROID_KEY_PATH/com.android.neuralnetworks.pem \
        --extra_apex_payload_key com.android.ondevicepersonalization.apex=$ANDROID_KEY_PATH/com.android.ondevicepersonalization.pem \
        --extra_apex_payload_key com.android.os.statsd.apex=$ANDROID_KEY_PATH/com.android.os.statsd.pem \
        --extra_apex_payload_key com.android.permission.apex=$ANDROID_KEY_PATH/com.android.permission.pem \
        --extra_apex_payload_key com.android.resolv.apex=$ANDROID_KEY_PATH/com.android.resolv.pem \
        --extra_apex_payload_key com.android.rkpd.apex=$ANDROID_KEY_PATH/com.android.rkpd.pem \
        --extra_apex_payload_key com.android.runtime.apex=$ANDROID_KEY_PATH/com.android.runtime.pem \
        --extra_apex_payload_key com.android.safetycenter.resources.apex=$ANDROID_KEY_PATH/com.android.safetycenter.resources.pem \
        --extra_apex_payload_key com.android.scheduling.apex=$ANDROID_KEY_PATH/com.android.scheduling.pem \
        --extra_apex_payload_key com.android.sdkext.apex=$ANDROID_KEY_PATH/com.android.sdkext.pem \
        --extra_apex_payload_key com.android.support.apexer.apex=$ANDROID_KEY_PATH/com.android.support.apexer.pem \
        --extra_apex_payload_key com.android.telephony.apex=$ANDROID_KEY_PATH/com.android.telephony.pem \
        --extra_apex_payload_key com.android.telephonymodules.apex=$ANDROID_KEY_PATH/com.android.telephonymodules.pem \
        --extra_apex_payload_key com.android.tethering.apex=$ANDROID_KEY_PATH/com.android.tethering.pem \
        --extra_apex_payload_key com.android.tzdata.apex=$ANDROID_KEY_PATH/com.android.tzdata.pem \
        --extra_apex_payload_key com.android.uwb.apex=$ANDROID_KEY_PATH/com.android.uwb.pem \
        --extra_apex_payload_key com.android.uwb.resources.apex=$ANDROID_KEY_PATH/com.android.uwb.resources.pem \
        --extra_apex_payload_key com.android.virt.apex=$ANDROID_KEY_PATH/com.android.virt.pem \
        --extra_apex_payload_key com.android.vndk.current.apex=$ANDROID_KEY_PATH/com.android.vndk.current.pem \
        --extra_apex_payload_key com.android.vndk.current.on_vendor.apex=$ANDROID_KEY_PATH/com.android.vndk.current.on_vendor.pem \
        --extra_apex_payload_key com.android.wifi.apex=$ANDROID_KEY_PATH/com.android.wifi.pem \
        --extra_apex_payload_key com.android.wifi.dialog.apex=$ANDROID_KEY_PATH/com.android.wifi.dialog.pem \
        --extra_apex_payload_key com.android.wifi.resources.apex=$ANDROID_KEY_PATH/com.android.wifi.resources.pem \
        --extra_apex_payload_key com.google.pixel.camera.hal.apex=$ANDROID_KEY_PATH/com.google.pixel.camera.hal.pem \
        --extra_apex_payload_key com.google.pixel.vibrator.hal.apex=$ANDROID_KEY_PATH/com.google.pixel.vibrator.hal.pem \
        --extra_apex_payload_key com.qorvo.uwb.apex=$ANDROID_KEY_PATH/com.qorvo.uwb.pem \
        $OUT/obj/PACKAGING/target_files_intermediates/*-target_files*.zip \
        $OUT/signed-target_files.zip
}

function genSignedOta() {
    ota_from_target_files -k $ANDROID_KEY_PATH/releasekey \
        --block --backup=true \
        $OUT/signed-target_files.zip \
        $OUT/signed-ota_update.zip
}

function extractSI() {
    local rising_build_version="$(get_build_var RISING_BUILD_VERSION)"
    rm -rf $OUT/signed_builds_images
    unzip $OUT/RisingOS-$rising_build_version-ota-signed.zip -d $OUT/signed_builds_images
    prebuilts/extract-tools/linux-x86/bin/ota_extractor --payload $OUT/signed_builds_images/payload.bin
    if [ ! -d "$OUT/signed_builds_images" ]; then
        mkdir $OUT/signed_builds_images
    fi
    rm -f $OUT/signed_builds_images/*.img
    if ls *.img 1> /dev/null 2>&1; then
        mv *.img $OUT/signed_builds_images
    else
        echo "No .img files found to move."
        return 1
    fi
}

function flashESI() {
    extractSI
    adb reboot fastboot &> /dev/null
    if ! command -v fastboot &> /dev/null; then
        echo "fastboot command not found."
        return 1
    fi
    if [ -f "$OUT/signed_builds_images/system.img" ]; then
        fastboot flash system $OUT/signed_builds_images/system.img || { echo "Failed to flash system.img"; return 1; }
    else
        echo "system.img not found in $OUT/signed_builds_images."
        return 1
    fi
    if [ -f "$OUT/signed_builds_images/system_ext.img" ]; then
        fastboot flash system_ext $OUT/signed_builds_images/system_ext.img || { echo "Failed to flash system_ext.img"; return 1; }
    else
        echo "system_ext.img not found in $OUT/signed_builds_images."
        return 1
    fi
    if [ -f "$OUT/signed_builds_images/product.img" ]; then
        fastboot flash product $OUT/signed_builds_images/product.img || { echo "Failed to flash product.img"; return 1; }
    else
        echo "product.img not found in $OUT/signed_builds_images."
        return 1
    fi
    fastboot reboot || { echo "Failed to reboot the device"; return 1; }
}

function dlawnchair() {
    REPO_OWNER="Goooler"
    REPO_NAME="LawnchairRelease"
    OUTPUT_DIR="vendor/addons/prebuilt/Lawnchair"
    APK_NAME="Lawnchair.apk"

    echo "Fetching latest release information..."
    mkdir -p "$OUTPUT_DIR"
    latest_release_url=$(curl -s https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest | grep "browser_download_url" | grep ".apk" | cut -d '"' -f 4)
    echo "Latest APK URL: $latest_release_url"
    echo "Downloading latest APK..."
    curl -L "$latest_release_url" -o "$OUTPUT_DIR/$APK_NAME"
    echo "Latest APK downloaded to $OUTPUT_DIR/$APK_NAME"
}

function dlawnicons() {
    REPO_OWNER="LawnchairLauncher"
    REPO_NAME="lawnicons"
    OUTPUT_DIR="vendor/addons/prebuilt/Lawnicons"
    APK_NAME="Lawnicons.apk"

    echo "Fetching latest release information..."
    mkdir -p "$OUTPUT_DIR"
    latest_release_url=$(curl -s https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest | grep "browser_download_url" | grep ".apk" | cut -d '"' -f 4)
    echo "Latest APK URL: $latest_release_url"
    echo "Downloading latest APK..."
    curl -L "$latest_release_url" -o "$OUTPUT_DIR/$APK_NAME"
    echo "Latest APK downloaded to $OUTPUT_DIR/$APK_NAME"
}

function rcleanup() {
    echo "Generating list of current repositories from the manifest files..."

    # Initialize current_repos.txt
    > current_repos.txt

    # Aggregate project names from manifest files in .repo/manifests
    for manifest in .repo/manifests/default.xml .repo/manifests/snippets/crdroid.xml .repo/manifests/snippets/lineage.xml .repo/manifests/snippets/pixel.xml .repo/manifests/snippets/rising.xml; 
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

alias adevtool='vendor/adevtool/bin/run'
alias adto='vendor/adevtool/bin/run'

remove_broken_build_tools
setup_ccache
validate_current_shell
set_global_paths
source_vendorsetup
addcompletions

export ANDROID_BUILD_TOP=$(gettop)
export ANDROID_KEY_PATH="$ANDROID_BUILD_TOP/vendor/lineage-priv/keys"

. $ANDROID_BUILD_TOP/vendor/lineage/build/envsetup.sh
