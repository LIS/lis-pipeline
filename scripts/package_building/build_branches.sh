#!/bin/bash

set -xe

. utils.sh

function get_branches() {
    git_dir="$1"
    ini_path="$2"
    
    if [[ "$ini_path" != "" ]];then
        ini_stable="$(crudini --get $ini_path BRANCHES kernel_stable)"
        INI_LAST_UNSTABLE="$(crudini --get $ini_path BRANCHES kernel_last_unstable)"
        INI_BRANCHES="$(split_string $ini_stable ,)"
    else
        exit 1
    fi  
    if [[ -d "$git_dir" ]];then
        SOURCE_STABLE="$(get_stable_branches $git_dir)"
        SOURCE_LAST_STABLE="$(get_latest_stable_branch $git_dir)"
        SOURCE_LAST_UNSTABLE="$(get_latest_unstable_branch $git_dir)"
        SOURCE_BRANCHES="$(split_string $SOURCE_STABLE ,)"
    else
        exit 1
    fi
}

function amend_ini() {
    ini_path="$1"
    git_dir="$2"
    stable="$3"
    last_stable="$4"
    last_unstable="$5"
    stable_branches=""
    
    for branch in "$stable";do
        stable_branches="${stable_branches},${stable}"
    done
    
    crudini --set "$ini_path" BRANCHES kernel_stable "${stable_branches#,*}"
    crudini --set "$ini_path" BRANCHES kernel_last_stable "${last_stable#}"
    crudini --set "$ini_path" BRANCHES kernel_last_unstable "${last_unstable#}"
    
    pushd "$git_dir"
    git add "$ini_path"
    git commit -m "Change kernel_versions.ini"
    git push
    popd
}

function start_job() {
    echo "$1"
}

function main() {
    GIT_DIR=""
    INI_PATH="$(readlink -e kernel_versions.ini)"
    BUILD_BRANCHES=""
    
    while true;do
        case "$1" in
            --git_folder)
                GIT_DIR="$2" 
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    get_branches "$GIT_DIR" "$INI_PATH"
    
    if [[ "$INI_LAST_UNSTABLE" != "SOURCE_LAST_UNSTABLE" ]];then
        BUILD_BRANCHES="$SOURCE_LAST_UNSTABLE"
    fi
    
    for source_branch in $SOURCE_BRANCHES;do
        branch_found="n"
        source_verison="${source_branch%#*}"
        source_tag="${source_branch#*#}"
        
        for ini_branch in $INI_BRANCHES;do
            ini_version="${ini_branch%#*}"
            ini_tag="${ini_branch#*#}"

            if [[ "$source_verison" == "$ini_version" ]] && [[ "$source_tag" == "$ini_tag" ]];then
                branch_found="y"
            fi    
        done
        if [[ "$branch_found" == "n" ]];then
            BUILD_BRANCHES="${BUILD_BRANCHES}:${source_branch}"
        fi
    done
    
    amend_ini "$INI_PATH" "$GIT_DIR" "$SOURCE_STABLE" "$SOURCE_LAST_STABLE" "$SOURCE_LAST_UNSTABLE"
    
    start_job "$BUILD_BRANCHES"
}

main $@
