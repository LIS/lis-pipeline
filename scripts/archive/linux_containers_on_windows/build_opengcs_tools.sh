#!/bin/bash

set -xe -o pipefail

source ~/.profile
source "./utils.sh"

OPENGCS_BASE_BUILD_DIR=""  # root location where building takes place, needs to be in GOPATH
OPENGCS_BUILD_DIR=""       # location where make is executed
OPENGCS_ARTIFACT_DIR=""    # location where artifacts are found after build

function build_opengcs() {
    opengcs_build_dir="$1"; shift
    thread_num="$1"

    echo "Building opengcs tools"

    if [[ ! -d "${opengcs_build_dir}" ]]; then
        echo "Could not find the opengcs directory to build"
        exit 1
    else
        pushd "${opengcs_build_dir}"
    fi

    echo "$PATH"
    make -j"${thread_num}" "bin/gcstools"
    popd

    echo "Opengcs tools artifacs built successfully"
}

function copy_opengcs_artifact() {
    opengcs_build_dir="$1"; shift
    opengcs_artifacts_destination_path="$1"; shift
    opengcs_artifact_dir="$1"

    output_dir_name="${opengcs_artifacts_destination_path}/`date +%Y%m%d`_${BUILD_ID}__opengcs"
    mkdir -p "${output_dir_name}"

    pushd "${opengcs_build_dir}"

    echo `git log --pretty=format:'%h' -n 1` > "${output_dir_name}/latest_opengcs_commit.log"
    echo "Opengcs tools built on commit:"
    cat "${output_dir_name}/latest_opengcs_commit.log"

    echo "Copying opengcs artifact to the destination folder"
    copy_artifacts "${opengcs_artifact_dir}" "${output_dir_name}"
    echo "Opengcs artifact published on ${output_dir_name}"
    echo "Opengcs tools artifacts copied successfully"

    popd
}

function cleanup_opengcs() {
    # Clean GO stuff
    opengcs_base_build_dir="$1"

    pushd "${opengcs_base_build_dir}"

    if [ -f go*.linux-amd64.tar.gz ]; then
        rm go*.linux-amd64.tar.gz
        echo "GO archive removed"
    fi

    if [ -d "${opengcs_base_build_dir}" ]; then
        rm -rf "${opengcs_base_build_dir}/golang/src/github.com/Microsoft/opengcs"
        echo "Git repos and GO dirs removed"
    fi

    echo "Cleanup successfull"
}

function copy_artifacts() {
    artifacts_folder="$1"; shift
    destination_path="$1"
    
    artifact_exists="$(ls $artifacts_folder/* || true)"
    if [[ "$artifact_exists" != "" ]];then
        cp "$artifacts_folder"/* "$destination_path"
    fi
}

function main {
    BUILD_BASE_DIR=""
    OPENGCS_ARTIFACTS_DESTINATION_PATH=""
    THREAD_NUM=""
    
    TEMP=$(getopt -o w:e:t: --long build_base_dir:,opengcs_artifacts_destination_path:,thread_num: -n 'build_opengcs_tools.sh' -- "$@")
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
            --opengcs_artifacts_destination_path)
                case "$2" in
                    "") shift 2 ;;
                    *) OPENGCS_ARTIFACTS_DESTINATION_PATH="$2" ; shift 2 ;;
                esac ;;
            --thread_num)
                case "$2" in
                    "") shift 2 ;;
                    *) THREAD_NUM=$(get_job_number "$2") ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) echo "Wrong parameters!" ; exit 1 ;;
        esac
    done

    OPENGCS_BASE_BUILD_DIR="${BUILD_BASE_DIR}/opengcs-build-folder"
    OPENGCS_BUILD_DIR="${GOPATH}/src/github.com/Microsoft/opengcs"
    OPENGCS_ARTIFACT_DIR="${OPENGCS_BUILD_DIR}/bin"

    echo "GOPATH is: $GOPATH"
    build_opengcs "$OPENGCS_BUILD_DIR" "$THREAD_NUM"
    copy_opengcs_artifact "$OPENGCS_BUILD_DIR" \
        "$OPENGCS_ARTIFACTS_DESTINATION_PATH" "$OPENGCS_ARTIFACT_DIR"
    
    echo "opengcs tools build successfully"
}

main "$@"
