#!/bin/bash

set -xe

function resolve_tree_state {
    repo_name="$1"
    kernel_tree="$2"
    
    if [[ -d $repo_name ]];then
        pushd "./${repo_name}"
        git pull
        popd
    else
        git clone $kernel_tree $repo_name
    fi
}

function get_latest_versions {
    repo_name="$1"

    pushd "./${repo_name}"
    # Get latest 2 versions
    ver="$(git tag | sort --version-sort --reverse | grep -E "^v[0-9]{1,3}\.[0-9]{1,3}$" -m2)"

    versions=""
    for i in $ver;do
        versions+="$i|"
    done
    echo ${versions::-1}
}

function get_latest_commits {
    repo_name="$1"
    versions="$2"
    results_path="$3"
    
    pushd "./${repo_name}"
    current_month="$(date +"%b" -d "yesterday")"
    current_day="$(date +"%d" -d "yesterday" | sed 's/^0*//')"
    current_year="$(date +"%Y" -d "yesterday")"

    full_tags="$(git tag -l --format='%(refname) %(taggerdate)' | grep "${current_month} ${current_day}" | grep "${current_year}" || true)"
    if [[ $versions ]];then
        full_tags="$(echo "$full_tags" | grep -E "$versions" || true)"
    fi
    tags="$(echo "$full_tags" | sed 's/ .*//' )"
    commits=""
    for tag in $tags;do
        commits+="${tag};"
    done
    if [[ $commits ]];then
        echo ${commits::-1} > $results_path
    fi
    popd
}

function main {
    
    while true;do
        case "$1" in
            --work_dir)
                WORK_DIR="$2" 
                shift 2;;
            --kernel_tree)
                KERNEL_TREE="$2" 
                shift 2;;
            --results)
                RESULTS_PATH="$(readlink -ef $2)"
                shift 2;;
            *) break ;;
        esac
    done
    
    if [[ ! $WORK_DIR || ! $KERNEL_TREE || ! $RESULTS_PATH ]];then
        echo "Error: Not enough parameters"
        exit 1
    fi
    if [[ ! -d $WORK_DIR ]];then
        mkdir -p $WORK_DIR
    fi
    if [[ -e $RESULTS_PATH ]];then
        rm $RESULTS_PATH
    fi
    touch $RESULTS_PATH
    REPO_NAME="$(basename "$KERNEL_TREE")"
    REPO_NAME="${REPO_NAME%.*}"
    
    pushd "$WORK_DIR"
    resolve_tree_state "$REPO_NAME" "$KERNEL_TREE"
    VERSIONS="$(get_latest_versions "$REPO_NAME")"
    get_latest_commits "$REPO_NAME" "$VERSIONS" "$RESULTS_PATH"
    popd
}

main $@
