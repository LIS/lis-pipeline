#!/bin/bash

set -xe -o pipefail

source ~/.profile
source "./utils.sh"

LINUX_BASE_DIR=""
OPENGCS_BASE_DIR=""

function apply_patches() {
    #
    # Apply some patches before building
    #
    linux_base_dir="$1"; shift
    linux_msft_artifacts_destination_path="$1"; shift
    kernel_version="$1"; shift
    checkout_commit="$1"; shift
    cherry_pick_commit="$1"; shift
    opengcs_base_dir="$1"; shift
    commits_list="$1"

    number_of_commits="0"
    IFS=$','
    for commit in ${COMMITS_LIST[@]}; do
        number_of_commits=$(( $number_of_commits + 1 ))
    done
    number_of_commits=$(( $number_of_commits + 1 ))
    IFS=$' '

    if [[ ! -d "${linux_base_dir}/msft_linux_kernel" ]]; then
        echo "Could not find the Linux Kernel repo to apply patches"
        exit 1
    else
        pushd "${linux_base_dir}/msft_linux_kernel"
    fi

    # this will be the destination directory of the kernel artifact
    output_dir_name="${linux_msft_artifacts_destination_path}/$(date +%Y%m%d)_${BUILD_ID}__msft-kernel_${kernel_version}"
    mkdir -p "${output_dir_name}"

    # last commit before pulling
    echo $(git log --pretty=format:'%h' -n 1) > "${output_dir_name}/latest_kernel_commit.log"
    echo "Linux kernel built on commit:"
    cat "${output_dir_name}/latest_kernel_commit.log"

    # tag for specific repo
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "${branch}" == "master" ]]; then
        git checkout "${checkout_commit}"
        #Note (papagalu): if the env is not clean, we have to revert all cherry-picks
        git reset --hard HEAD~${number_of_commits}
        git cherry-pick "$cherry_pick_commit"

        echo "Apply NVDIMM patch"
        patch -p1 -t <"${opengcs_base_dir}/kernel/patches-4.12.x/0002-NVDIMM-reducded-ND_MIN_NAMESPACE_SIZE-from-4MB-to-4K.patch"
        cp "${opengcs_base_dir}/kernel/kernel_config-${kernel_version}.x" .config

        echo "Instructions for getting Hyper-V vsock patch"
        git remote add -f dexuan-github https://github.com/dcui/linux.git  || echo "already existing"
        git fetch dexuan-github

        IFS=$','
        for commit in ${COMMITS_LIST[@]}; do
            git cherry-pick -x "${commit}"
        done
        IFS=$' '

        popd
        echo "Patches applied on Linux Kernel successfully"
    fi
}

function build_kernel() {
    linux_base_dir="$1"; shift
    linux_msft_artifacts_destination_path="$1"; shift
    kernel_version="$1"; shift
    thread_num="$1"

    pushd "${linux_base_dir}/msft_linux_kernel"

    echo "Building the LCOW MS-Linux kernel"
    fakeroot make -j"${thread_num}" && fakeroot make modules
    if [[ $? -eq 0 ]]; then
        echo "Kernel built successfully"
    else
        echo "Kernel building failed"
    fi

    # only need the vmlinuz file"
    cp "./arch/x86/boot/bzImage" "${output_dir_name}/bootx64.efi"
    if [[ $? -eq 0 ]]; then
        echo "Kernel artifact published on ${output_dir_name}"
    else
        echo "Could not copy Kernel artifact to ${output_dir_name}"
    fi

    popd
}

function main {
    BUILD_BASE_DIR=""
    LINUX_MSFT_ARTIFACTS_DESTINATION_PATH=""
    THREAD_NUM=""
    KERNEL_VERSION=""
    CHECKOUT_COMMIT=""
    CHERRY_PICK_COMMIT=""
    COMMITS_LIST=""

    TEMP=$(getopt -o w:e:t:y:u:i:o: --long build_base_dir:,linux_artifacts_destination_path:,thread_num:,kernel_version:,checkout_commit:,cherry_pick_commit:,commits_list: -n 'build_linux_kernel.sh' -- "$@")
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
            --linux_artifacts_destination_path)
                case "$2" in
                    "") shift 2 ;;
                    *) LINUX_MSFT_ARTIFACTS_DESTINATION_PATH="$2" ; shift 2 ;;
                esac ;;
            --thread_num)
                case "$2" in
                    "") shift 2 ;;
                    *) THREAD_NUM=$(get_job_number "$2") ; shift 2 ;;
                esac ;;
            --kernel_version)
                case "$2" in
                    "") shift 2 ;;
                    *) KERNEL_VERSION="$2" ; shift 2 ;;
                esac ;;
            --checkout_commit)
                case "$2" in
                    "") shift 2 ;;
                    *) CHECKOUT_COMMIT="$2" ; shift 2 ;;
                esac ;;
            --cherry_pick_commit)
                case "$2" in
                    "") shift 2 ;;
                    *) CHERRY_PICK_COMMIT="$2" ; shift 2 ;;
                esac ;;
            --commits_list)
                case "$2" in
                    "") shift 2 ;;
                    *) COMMITS_LIST="$2" ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) echo "Wrong parameters!" ; exit 1 ;;
        esac
    done

    LINUX_BASE_DIR="${BUILD_BASE_DIR}/kernel-build-folder"
    OPENGCS_BASE_DIR="${BUILD_BASE_DIR}/opengcs-build-folder/golang/src/github.com/Microsoft/opengcs"

    apply_patches "$LINUX_BASE_DIR" "$LINUX_MSFT_ARTIFACTS_DESTINATION_PATH" \
        "$KERNEL_VERSION" "$CHECKOUT_COMMIT" "$CHERRY_PICK_COMMIT" \
        "$OPENGCS_BASE_DIR" "$COMMITS_LIST"
    build_kernel "$LINUX_BASE_DIR" "$LINUX_MSFT_ARTIFACTS_DESTINATION_PATH" \
        "$KERNEL_VERSION" "$THREAD_NUM"
}

main "$@"
