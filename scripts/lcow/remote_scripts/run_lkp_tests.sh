#!/bin/bash

PACKAGES="lsb-release sudo build-essential git wget"
RUN_TESTS=("analyze_suspend.yaml" "autotest.yaml" "dbench.yaml" "ebizzy.yaml" "pm-qa.yaml" "trinity.yaml")

set -x

function install_dependencies {
    packages="$1"
    
    apt update
    apt install -y $packages 
}

function copy_logs {
    results_path="$1"
    log_dir="$2"
    test_name="$3"
    
    mkdir "${log_dir}/${test_name}"
    cp ${results_path}* "${log_dir}/${test_name}"
}

function run_tests {
    log_dir="$1"

    git clone https://github.com/fengguang/lkp-tests.git .
    make install
    if [[ $? -ne 0 ]];then
        echo "lkp make failed"
        exit 1
    fi
    yes | lkp install
    if [[ $? -ne 0 ]];then
        echo "lkp deps install failed"
        exit 1
    fi
    
    for test in ${RUN_TESTS[@]};do
        test_path="./jobs/${test}"
        test_name="${test%.*}"
        
        lkp install $test_path
        lkp run $test_path
        results_path="$(lkp result $test_name)"
        if [[ -d "$results_path" ]];then
            copy_logs "$results_path" "$log_dir" "$test_name"
        else
            echo "${test}" >> "$log_dir/ABORT" 
            echo "Cannot find logs dir for test: $test_name"
            continue
        fi
    done
}

function main {
    WORK_DIR=""
    LOG_DIR=""
    
    while true;do
        case "$1" in
            --work_dir)
                WORK_DIR="$2"
                shift 2;;
            --log_dir)
                LOG_DIR="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ ! -e "$WORK_DIR" ]];then
        mkdir -p "$WORK_DIR"
    else
        rm -rf "$WORK_DIR"
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
    
    pushd "$WORK_DIR"

    run_tests "$LOG_DIR"
    popd
}

main $@