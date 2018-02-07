#!/bin/bash

set -xe

. utils.sh

source ~/.profile

BUILD_BASE_DIR="$1"
OPENGCS_ARTIFACTS_DESTINATION_PATH="$2"
THREAD_NUM="$3"

# root location where building takes place, needs to be in GOPATH
OPENGCS_BASE_BUILD_DIR="$BUILD_BASE_DIR/opengcs-build-folder"
# location where make is executed
OPENGCS_BUILD_DIR="$GOPATH/src/github.com/Microsoft/opengcs/service"
#location where artifacts are found after build
OPENGCS_ARTIFACT_DIR="$OPENGCS_BUILD_DIR/bin"

function build_opengcs() {
    sudo chown -R `whoami`:`whoami` $GOPATH
    sudo chown -R `whoami`:`whoami` $GOROOT
    echo "Building opengcs tools"

    if [ ! -d "$OPENGCS_BUILD_DIR" ];then
        echo "Could not find the opengcs rep to build"
        exit 1
    else
        pushd "$OPENGCS_BUILD_DIR"
    fi

    echo $PATH
    make -j"$THREAD_NUM"
    popd

    echo "Opengcs tools artifacs built successfully"
}

function copy_opengcs_artifact() {
    output_dir_name=$OPENGCS_ARTIFACTS_DESTINATION_PATH/`date +%Y%m%d`_${BUILD_ID}__opengcs
    sudo mkdir -p $output_dir_name

    pushd $OPENGCS_BUILD_DIR

    echo `git log --pretty=format:'%h' -n 1` > $output_dir_name/latest_opengcs_commit.log
    echo "Opengcs tools built on commit:"
    cat $output_dir_name/latest_opengcs_commit.log

    echo "Copying opengcs artifact to the destination folder"
    copy_artifacts "$OPENGCS_ARTIFACT_DIR" $output_dir_name
    echo "Opengcs artifact published on $output_dir_name"
    echo "Opengcs tools artifacts copied successfully"

    popd

}

function cleanup_opengcs() {
    # Clean GO stuff
    pushd "$OPENGCS_BASE_BUILD_DIR"

    if [ -f go*.linux-amd64.tar.gz ]; then
        rm go*.linux-amd64.tar.gz
        echo "GO archive removed"
    fi

    if [ -d "$OPENGCS_BASE_BUILD_DIR" ]; then
        rm -rf "$OPENGCS_BASE_BUILD_DIR/go"
        rm -rf "$OPENGCS_BASE_BUILD_DIR/golang"
        echo "Git repos and GO dirs removed"
    fi

    echo "Cleanup successfull"
}

echo "GOPATH is: $GOPATH"
build_opengcs
copy_opengcs_artifact

echo "opengcs tools build successfully"

cleanup_opengcs