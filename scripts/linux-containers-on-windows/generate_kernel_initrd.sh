#!/bin/bash

set -xe

. utils.sh

# root location of the already build kernel and opengcs artifacts
KERNEL_ARTIFACTS_PATH="$1"
OPENGCS_ARTIFACTS_PATH="$2"
# locations of the extra packages that need to go into the initrd
BUILD_EXTRA_ARTIFACTS="$3"
BUILD_BASE_DIR="$4"
KERNEL_VERSION="$5"


BUILD_PATH="$BUILD_BASE_DIR/kernel-build-folder/initrd_build"
KERNEL_ARTIFACT_DIR_PATH=$(ls -td -- "$KERNEL_ARTIFACTS_PATH"/* |  grep  __msft-kernel_$KERNEL_VERSION | head -n 1)
OPENGCS_ARTIFACT_DIR_PATH=$(ls -td -- $OPENGCS_ARTIFACTS_PATH/* |  grep __opengcs | head -n 1)

function get_kernel_bits() {
    # here is where the initrd generate will take place, can't see any other reason to
    # do this somewhere else
    if [ -d "$KERNEL_ARTIFACT_DIR_PATH" ]
    then
        pushd "$BUILD_PATH"
        vmlinuz_file="bootx64.efi"
        sudo cp "$KERNEL_ARTIFACT_DIR_PATH/$vmlinuz_file" .
        popd
        echo "Kernel artifacts copied from $KERNEL_ARTIFACT_DIR_PATH/$vmlinuz_file to $BUILD_PATH"
    else
        echo "Kernel artifacts folder not found"
    exit 1
   fi
}

function get_opengcs_bits() {
    # copy the opengc bits to the location where initrd is generated
    if [ -d "$OPENGCS_ARTIFACT_DIR_PATH" ]
    then
        pushd "$BUILD_PATH"
        sudo cp -r $OPENGCS_ARTIFACT_DIR_PATH/* .
        popd
        echo "Kernel artifacts copied for initrd generation"
    else
    echo "Opengcs artifacts folder not found"
    exit 1
    fi
}

function generate_initrd() {
    # where the generating takes place
    sudo chown -R `whoami`:`whoami` $BUILD_PATH
    pushd "$BUILD_PATH"

    # create the initd artifact directory on the share
    sudo mkdir -p "$KERNEL_ARTIFACT_DIR_PATH/initrd_artifact"
    # create the initrd artifact directory where it's building
    sudo mkdir -p ./initrd_artifact

    # copy opengcs bits into the extra build artifacts
    sudo cp -al $BUILD_EXTRA_ARTIFACTS .
    sudo chown -R `whoami`:`whoami` $BUILD_PATH
    sudo cp $OPENGCS_ARTIFACT_DIR_PATH/* ./temp/bin
    #sudo cp $OPENGCS_ARTIFACT_DIR_PATH/gcstools ./temp/bin

    sudo ln -f ./temp/bin/gcstools ./temp/bin/exportSandbox
    sudo ln -f ./temp/bin/gcstools ./temp/bin/vhd2tar
    sudo ln -f ./temp/bin/gcstools ./temp/bin/tar2vhd
    sudo ln -f ./temp/bin/gcstools ./temp/bin/remotefs
    sudo ln -f ./temp/bin/gcstools ./temp/bin/netnscfg

    # generate initrd and put it in ./initrd_artifacts with
    # kernel artifacts root path
    pushd ./temp
    sudo find . | sudo cpio -o --format="newc" | sudo gzip -c > ../newInitrd
    popd

    sudo cp newInitrd ./initrd_artifact/initrd.img
    echo "Initrd generated successfully"
    sudo cp ./initrd_artifact/initrd.img $KERNEL_ARTIFACT_DIR_PATH/initrd_artifact/initrd.img
    echo "Initrd artifact published on $KERNEL_ARTIFACT_DIR_PATH/initrd_artifact"
    echo "Initrd copied to share successfully"

    popd
}

function cleanup() {
    if [ -d "$BUILD_PATH" ]
    then
        sudo rm -rf "$BUILD_PATH"
    fi
}

cleanup

if [ ! -d "$BUILD_PATH" ]
then
    sudo mkdir -p "$BUILD_PATH"
fi

#get_kernel_bits
get_opengcs_bits
generate_initrd