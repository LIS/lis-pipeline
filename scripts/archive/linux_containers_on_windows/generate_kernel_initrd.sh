#!/bin/bash

set -xe -o pipefail

BUILD_PATH=""
KERNEL_ARTIFACT_DIR_PATH=""
OPENGCS_ARTIFACT_DIR_PATH=""

function get_kernel_bits() {
    if [[ -d "$KERNEL_ARTIFACT_DIR_PATH" ]]; then
        pushd "$BUILD_PATH"
        vmlinuz_file="bootx64.efi"
        cp "${KERNEL_ARTIFACT_DIR_PATH}/${vmlinuz_file}" .
        popd
        echo "Kernel artifacts copied from \
            ${KERNEL_ARTIFACT_DIR_PATH}/${vmlinuz_file} to $BUILD_PATH"
    else
        echo "Kernel artifacts folder not found"
    exit 1
   fi
}

function get_opengcs_bits() {
    # copy the opengc bits to the location where initrd is generated
    if [[ -d "$OPENGCS_ARTIFACT_DIR_PATH" ]]; then
        pushd "$BUILD_PATH"
        cp -r $OPENGCS_ARTIFACT_DIR_PATH/* .
        popd
        echo "Kernel artifacts copied for initrd generation"
    else
    echo "Opengcs artifacts folder not found"
    exit 1
    fi
}

function generate_initrd() {
    # where the generating takes place
    pushd "$BUILD_PATH"

    # create the initd artifact directory on the share
    mkdir -p "$KERNEL_ARTIFACT_DIR_PATH/initrd_artifact"
    # create the initrd artifact directory where it's building
    mkdir -p ./initrd_artifact

    # copy opengcs bits into the extra build artifacts
    cp -al "$BUILD_EXTRA_ARTIFACTS" .
    cp $OPENGCS_ARTIFACT_DIR_PATH/* ./temp/bin

    ln -f ./temp/bin/gcstools ./temp/bin/exportSandbox
    ln -f ./temp/bin/gcstools ./temp/bin/vhd2tar
    ln -f ./temp/bin/gcstools ./temp/bin/tar2vhd
    ln -f ./temp/bin/gcstools ./temp/bin/remotefs
    ln -f ./temp/bin/gcstools ./temp/bin/netnscfg

    # generate initrd and put it in ./initrd_artifacts with
    # kernel artifacts root path
    pushd ./temp
    find . | cpio -o --format="newc" | gzip -c > ../newInitrd
    popd

    cp newInitrd ./initrd_artifact/initrd.img
    echo "Initrd generated successfully"
    cp ./initrd_artifact/initrd.img "${KERNEL_ARTIFACT_DIR_PATH}/initrd_artifact/initrd.img"
    echo "Initrd artifact published on ${KERNEL_ARTIFACT_DIR_PATH}/initrd_artifact"
    echo "Initrd copied to share successfully"

    popd
}

function cleanup() {
    build_path="$1"
    if [[ -d "$build_path" ]]; then
        rm -rf "$build_path"
    fi
}

function main {
    KERNEL_ARTIFACTS_PATH="" # root location of the already build kernel and opengcs artifacts
    BUILD_EXTRA_ARTIFACTS="" # locations of the extra packages that need to go into the initrd
    BUILD_BASE_DIR=""
    KERNEL_VERSION=""
    CLEAN_ENV=""

    TEMP=$(getopt -o w:e:t:y:u: --long kernel_artifacts_path:,build_extra_artifacts:,build_base_dir:,kernel_version:,clean_env: -n 'generate_initrd.sh' -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    echo $TEMP

    eval set -- "$TEMP"

    while true ; do
        case "$1" in
            --build_base_dir)
                case "$2" in
                    "") shift 2 ;;
                    *) BUILD_BASE_DIR="$2" ; shift 2 ;;
                esac ;;
            --kernel_artifacts_path)
                case "$2" in
                    "") shift 2 ;;
                    *) KERNEL_ARTIFACTS_PATH="$2" ; shift 2 ;;
                esac ;;
            --kernel_version)
                case "$2" in
                    "") shift 2 ;;
                    *) KERNEL_VERSION="$2" ; shift 2 ;;
                esac ;;
            --build_extra_artifacts)
                case "$2" in
                    "") shift 2 ;;
                    *) BUILD_EXTRA_ARTIFACTS="$2" ; shift 2 ;;
                esac ;;
            --clean_env)
                case "$2" in
                    "") shift 2 ;;
                    *) CLEAN_ENV="$2" ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) echo "Wrong parameters!" ; exit 1 ;;
        esac
    done

    BUILD_PATH="${BUILD_BASE_DIR}/kernel-build-folder/initrd_build"
    KERNEL_ARTIFACT_DIR_PATH=$(ls -td -- "$KERNEL_ARTIFACTS_PATH"/* | \
        grep __msft-kernel_$KERNEL_VERSION | head -n 1)
    OPENGCS_ARTIFACT_DIR_PATH=$(ls -td -- $KERNEL_ARTIFACTS_PATH/* | \
        grep __opengcs | head -n 1)

    if [[ "$CLEAN_ENV" == "True" ]]; then
        cleanup "$BUILD_PATH"
    fi
    
    if [[ ! -d "$BUILD_PATH" ]]; then
        mkdir -p "$BUILD_PATH"
    fi

    get_kernel_bits
    get_opengcs_bits
    generate_initrd
}

main "$@"
