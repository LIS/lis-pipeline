#!/bin/bash

# This script installs GO + clones linux kernel & opengcs tools
set -xe

. utils.sh

GO_VERSION="$1"

LINUX_MSFT_GIT_URL="$2"
LINUX_MSFT_GIT_BRANCH="$3"
OPENGCS_GIT_URL="$4"
OPENGCS_GIT_BRANCH="$5"
BUILD_BASE_DIR="$6"

LINUX_BASE_DIR="$BUILD_BASE_DIR/kernel-build-folder"
OPENGCS_BASE_DIR="$BUILD_BASE_DIR/opengcs-build-folder"

function install_deps() {
    # installing packages required for the build process.
    sudo apt -y install build-essential bc

    # install GO
    pushd $OPENGCS_BASE_DIR
    if [ ! -d ./go ]
    then
        curl -O https://storage.googleapis.com/golang/go"$GO_VERSION".linux-amd64.tar.gz
        tar -xvf go"$GO_VERSION".linux-amd64.tar.gz
    fi

    # configure the GO paths
    if ! grep "GOPATH" ~/.profile
    then
        echo "export GOROOT=$OPENGCS_BASE_DIR/go" >> ~/.profile
        echo "export GOPATH=$OPENGCS_BASE_DIR/golang" >> ~/.profile
        echo 'export PATH=$PATH:$GOROOT/bin' >> ~/.profile
    fi

    source ~/.profile
    popd
}

function clone_opengcs_git() {
    if [ ! -d "$OPENGCS_SOURCES_DIR/opengcs" ]
    then
        echo "Cloning opengcs repository"
        sudo mkdir -p "$OPENGCS_SOURCES_DIR"
        pushd "$OPENGCS_SOURCES_DIR"
        sudo git clone "$OPENGCS_GIT_URL" -b "$OPENGCS_GIT_BRANCH" opengcs
        popd
    else
        echo "Repository already exists"
        pushd "$OPENGCS_SOURCES_DIR/opengcs"
        sudo git pull
        popd 
    fi
}

function clone_linux_git() {
    if [ ! -d "$LINUX_BASE_DIR/msft_linux_kernel" ]
    then
        echo "Cloning linux-msft repository"
        pushd "$LINUX_BASE_DIR"
        git clone "$LINUX_MSFT_GIT_URL" -b "$LINUX_MSFT_GIT_BRANCH" msft_linux_kernel
        popd
    else
        echo "Repository already exists"
    fi
}

function cleanup() {
    if [ -d "$LINUX_BASE_DIR/msft_linux_kernel" ]
    then
        sudo rm -rf $LINUX_BASE_DIR/msft_linux_kernel
    fi

    if [ -d "$OPENGCS_SOURCES_DIR/opengcs" ]
    then
        sudo rm -rf $OPENGCS_SOURCES_DIR/opengcs
    fi
}

install_deps $OPENGCS_BASE_DIR

OPENGCS_SOURCES_DIR="$GOPATH/src/github.com/Microsoft"

cleanup
clone_opengcs_git 
clone_linux_git