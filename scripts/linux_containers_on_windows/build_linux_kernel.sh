#!/bin/bash

set -xe

. utils.sh

source ~/.profile

# base dir in which the artifacts are going to be built
BUILD_BASE_DIR="$1"
LINUX_MSFT_ARTIFACTS_DESTINATION_PATH="$2"
THREAD_NUM="$3"
KERNEL_VERSION="$4"
CHECKOUT_COMMIT="$5"
COMMITS_LIST="$6"

# the kernel is going to be built here
LINUX_BASE_DIR="$BUILD_BASE_DIR/kernel-build-folder"
# opengcs tools are going to be built here, needs to be in GOPATH
OPENGCS_BASE_DIR="$BUILD_BASE_DIR/opengcs-build-folder/golang/src/github.com/Microsoft/opengcs"


function apply_patches() {
    if [ ! -d "$LINUX_BASE_DIR/msft_linux_kernel" ];then
        echo "Could not find the Linux Kernel repo to apply patches"
        exit 1
    else
        pushd "$LINUX_BASE_DIR/msft_linux_kernel"
    fi

    output_dir_name=$LINUX_MSFT_ARTIFACTS_DESTINATION_PATH/`date +%Y%m%d`_${BUILD_ID}__msft-kernel_$KERNEL_VERSION
    sudo mkdir -p $output_dir_name

    echo `git log --pretty=format:'%h' -n 1` > $output_dir_name/latest_kernel_commit.log
    echo "Linux kernel built on commit:"
    cat $output_dir_name/latest_kernel_commit.log

    # tag for specific repo
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$branch" == "master" ]
    then
        git checkout "$CHECKOUT_COMMIT"
        git cherry-pick fd96b8da68d32a9403726db09b229f4b5ac849c7

        echo "Apply NVDIMM patch"
        patch -p1 -t <$OPENGCS_BASE_DIR/kernel/patches-4.12.x/0002-NVDIMM-reducded-ND_MIN_NAMESPACE_SIZE-from-4MB-to-4K.patch
        cp $OPENGCS_BASE_DIR/kernel/kernel_config-4.12.x .config

        echo "Instructions for getting Hyper-V vsock patch"
        git remote add -f dexuan-github https://github.com/dcui/linux.git  || echo "already existing"
        git fetch dexuan-github


        for commit in ${COMMITS_LIST[@]}
        do
            git cherry-pick -x ${commit}
        done

        popd
        echo "Patches applied on Linux Kernel successfully"
    fi
}

function build_kernel() {
    sudo chown -R `whoami`:`whoami` $LINUX_BASE_DIR/msft_linux_kernel
    pushd $LINUX_BASE_DIR/msft_linux_kernel

    echo "Building the LCOW MS-Linux kernel"
    sudo make -j"$THREAD_NUM" && sudo make modules
    if [ $? -eq 0 ]
    then
        echo "Kernel built successfully"
    else
        echo "Kernel building failed"
    fi

    output_dir_name=$LINUX_MSFT_ARTIFACTS_DESTINATION_PATH/`date +%Y%m%d`_${BUILD_ID}__msft-kernel_$KERNEL_VERSION

    # only need the vmlinuz file"
    sudo cp "./arch/x86/boot/bzImage" "$output_dir_name/bootx64.efi"
    if [ $? -eq 0 ]
    then
        echo "Kernel artifact published on $output_dir_name"
    else
        echo "Could not copy Kernel artifact to $output_dir_name"
    fi

    popd
}

apply_patches 
build_kernel

