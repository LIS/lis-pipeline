#!/bin/bash

PACKAGES="lsb-release sudo build-essential default-jre npm wget"
IGNORE_TESTS=""
LOG_FILE_SUFIX="_exec.log"
SUMMARY_NAME="summary.log"

set -x

function install_dependencies {
    packages="$1"
    
    apt update
    apt install -y $packages
}

function run_tests {
    for script in $(ls *.sh);do
        if [[ ! $(echo "${IGNORE_TESTS}" | grep "${script}") ]];then
            echo "~~~~ Running ${script} ~~~~"
            bash "${script}" 2>&1 | tee "${script}${LOG_FILE_SUFIX}"
            echo "${script} exit code:${PIPESTATUS[0]}" >> "./${SUMMARY_NAME}"
        else
            echo "${script}:SKIP" >> "./${SUMMARY_NAME}"
        fi
    done
}

function copy_logs {
    log_dir="$1"

    cp "${TESTS_DIR}/testscripts/${SUMMARY_NAME}" "$log_dir"
    cp ${TESTS_DIR}/testscripts/*${LOG_FILE_SUFIX} "$log_dir"
}

function main {
    TESTS_DIR=""
    LOG_DIR=""
    
    while true;do
        case "$1" in
            --tests_dir)
                TESTS_DIR="$(readlink -e $2)"
                shift 2;;
            --log_dir)
                LOG_DIR="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ ! -e "$TESTS_DIR" ]];then
        echo "Cannot find test directory"
        exit 1
    fi  
    if [[ -e "$LOG_DIR" ]];then
        rm -rf "${LOG_DIR}/*"
    else
        mkdir "$LOG_DIR"
    fi
    LOG_DIR="$(readlink -e $LOG_DIR)"
    
    if [[ "${PACKAGES}" != "" ]];then
        install_dependencies "$PACKAGES"
    fi

    pushd "$TESTS_DIR/testscripts"
    ls -R .
    run_tests
    copy_logs "$LOG_DIR"
    popd
}

main $@
