#!/bin/bash

PACKAGES=(git lsb-release sudo build-essential wget autoconf automake m4 libaio-dev libattr1
          libcap-dev bison libdb4.8 libberkeleydb-perl flex expect)

TESTS = "fs,fs_bind,fs_ext4,fs_perms_simple,fs_readonly"

set -x
WORK_DIR="/opt/ltp"

function install_dependencies {
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y ${PACKAGES[@]}
}

function copy_logs {
    log_dir="$1"

    cp ${WORK_DIR}/results/*.log "$log_dir"
}

function main {
    CLONE_DIR=""
    LOG_DIR=""
    
    while true;do
        case "$1" in
            --clone_dir)
                CLONE_DIR="$(readlink -e $2)"
                shift 2;;
            --log_dir)
                LOG_DIR="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ ! -e "$CLONE_DIR" ]];then
        echo "Cannot find test directory"
        exit 1
    fi  
    if [[ -e "$LOG_DIR" ]];then
        rm -rf "${LOG_DIR}/*"
    else
        mkdir "$LOG_DIR"
    fi
    LOG_DIR="$(readlink -e $LOG_DIR)"
    
    install_dependencies

    pushd $CLONE_DIR
    git clone https://github.com/linux-test-project/ltp
    
    pushd "./ltp"
    make autotools
    if [ $? -gt 0 ];then
        echo "Autotools build failed"
        exit 1
    fi
    
    bash ./configure
    
    make
    if [ $? -gt 0 ];then
        echo "Tests build failed"
        exit 1
    fi
    make install
    if [ $? -gt 0 ];then
        echo "Tests install failed"
        exit 1
    fi
    popd
    popd
    
    pushd "$WORK_DIR"
    touch /dev/kmsg
    bash ./runltp -f "$TESTS"
    copy_logs "$LOG_DIR"
    popd
}

main $@
