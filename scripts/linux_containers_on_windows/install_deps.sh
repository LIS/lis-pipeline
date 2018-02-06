#!/bin/bash

# This script installs GO + clones linux kernel & opengcs tools
set -xe -o pipefail

LINUX_BASE_DIR=""
OPENGCS_BASE_DIR=""

function install_deps() {
    #
    # Installing packages required for the build process.
    #
    opengcs_base_dir="$1"

    sudo apt update -y && sudo apt dist-upgrade -y
    sudo apt -y install build-essential bc git

    mkdir -p "${opengcs_base_dir}" && pushd "${opengcs_base_dir}"

    # install GO if needed
    if [[ ! -d ./go ]]; then
        curl -O https://storage.googleapis.com/golang/go1.9.2.linux-amd64.tar.gz
        tar -xvf go1.9.2.linux-amd64.tar.gz 1>/dev/null
    fi

    # configure the GO paths
    if ! grep "GOPATH" ~/.profile ; then
        echo "export GOROOT=${OPENGCS_BASE_DIR}/go" >> ~/.profile
        echo "export GOPATH=${OPENGCS_BASE_DIR}/golang" >> ~/.profile
        echo "export PATH=${PATH}:${GOROOT}/bin" >> ~/.profile
    fi

    source ~/.profile
    mkdir -p "${GOPATH}/src/github.com/Microsoft"
    popd
}

function clone_opengcs_git() {
    opengcs_sources_dir="$1"; shift
    opengcs_git_url="$1"; shift
    opengcs_git_branch="$1"; shift

    if [[ ! -d "${opengcs_sources_dir}/opengcs" ]]; then
        echo "Cloning opengcs repository"
        pushd "${opengcs_sources_dir}"
        git clone "${opengcs_git_url}" -b "${opengcs_git_branch}" opengcs
        popd
    else
        echo "Repository already exists, pulling"
        pushd "${opengcs_sources_dir}/opengcs"
        git checkout -f master > /dev/null
        git reset
        git pull 2>&1 > /dev/null
        popd 
    fi
}

function clone_linux_git() {
    linux_base_dir="$1"; shift
    linux_msft_git_url="$1"; shift
    linux_msft_git_branch="$1"

    mkdir -p "${linux_base_dir}"

    if [[ ! -d "${linux_base_dir}/msft_linux_kernel" ]]; then
        echo "Cloning linux-msft repository"
        pushd "${linux_base_dir}"
        git clone "${linux_msft_git_url}" -b "${linux_msft_git_branch}" msft_linux_kernel
        popd
    else
        echo "Repository already exists, pulling"
        pushd "${linux_base_dir}/msft_linux_kernel"
        git checkout -f master > /dev/null
        git reset --hard HEAD~20
        git pull 2>&1 > /dev/null
        popd
    fi
}

function cleanup() {
    #
    # Cleanup the env 
    #
    linux_base_dir="$1"; shift
    opengcs_sources_dir="$1"

    if [[ -d "${linux_base_dir}/msft_linux_kernel" ]]; then
        rm -rf "${linux_base_dir}/msft_linux_kernel"
    fi

    if [[ -d "${opengcs_sources_dir}/opengcs" ]]; then
        rm -rf "${opengcs_sources_dir}/opengcs"
    fi
}

function main {
    LINUX_MSFT_GIT_URL=""
    LINUX_MSFT_GIT_BRANCH=""
    OPENGCS_GIT_URL=""
    OPENGCS_GIT_BRANCH=""
    BUILD_BASE_DIR=""
    CLEAN_ENV=""

    TEMP=$(getopt -o w:e:t:y:u:i: --long linux_git_url:,linux_git_branch:,opengcs_git_url:,opengcs_git_branch:,build_base_dir:,clean_env: -n 'install_deps.sh' -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    echo $TEMP

    eval set -- "$TEMP"

    while true ; do
        case "$1" in
            --linux_git_url)
                case "$2" in
                    "") shift 2 ;;
                    *) LINUX_MSFT_GIT_URL="$2" ; shift 2 ;;
                esac ;;
            --linux_git_branch)
                case "$2" in
                    "") shift 2 ;;
                    *) LINUX_MSFT_GIT_BRANCH="$2" ; shift 2 ;;
                esac ;;
            --opengcs_git_url)
                case "$2" in
                    "") shift 2 ;;
                    *) OPENGCS_GIT_URL="$2" ; shift 2 ;;
                esac ;;
            --opengcs_git_branch)
                case "$2" in
                    "") shift 2 ;;
                    *) OPENGCS_GIT_BRANCH="$2" ; shift 2 ;;
                esac ;;
            --clean_env)
                case "$2" in
                    "") shift 2 ;;
                    *) CLEAN_ENV="$2" ; shift 2 ;;
                esac ;;
            --build_base_dir)
                case "$2" in
                    "") shift 2 ;;
                    *) BUILD_BASE_DIR="$2" ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) echo "Wrong parameters!" ; exit 1 ;;
        esac
    done

    LINUX_BASE_DIR="${BUILD_BASE_DIR}/kernel-build-folder"
    OPENGCS_BASE_DIR="${BUILD_BASE_DIR}/opengcs-build-folder"

    install_deps "$OPENGCS_BASE_DIR"

    OPENGCS_SOURCES_DIR="${GOPATH}/src/github.com/Microsoft"

    if [[ "$CLEAN_ENV" == "True" ]]; then
        cleanup "$LINUX_BASE_DIR" "$OPENGCS_SOURCES_DIR"
    fi

    clone_opengcs_git "$OPENGCS_SOURCES_DIR" "$OPENGCS_GIT_URL" "$OPENGCS_GIT_BRANCH"
    clone_linux_git "$LINUX_BASE_DIR" "$LINUX_MSFT_GIT_URL" "$LINUX_MSFT_GIT_BRANCH"

}

main "$@"
