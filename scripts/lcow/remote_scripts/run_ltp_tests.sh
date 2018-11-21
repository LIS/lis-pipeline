#!/bin/bash

PACKAGES=(git lsb-release sudo build-essential wget autoconf automake m4 libaio-dev libattr1
          libcap-dev bison libdb4.8 libberkeleydb-perl flex expect)

IGNORE_TESTS="shmctl05 fanotify01 mlockall01 inotify09 mtest06 memcg_stress controllers cpuset_inherit cpuset_hotplug"
IGNORE_TESTS="$(echo $IGNORE_TESTS | tr " " "\n")"

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

function create_skip_file {
    file_path="$1"
    
    cat << EOF > "$file_path"
$IGNORE_TESTS
EOF
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
    
    if [[ "$IGNORE_TESTS" != "" ]];then
        create_skip_file "${WORK_DIR}/SKIP_TESTS"
    fi
    
    touch /dev/kmsg
    bash ./runltp -S "${WORK_DIR}/SKIP_TESTS"
    copy_logs "$LOG_DIR"
    popd
}

main $@
