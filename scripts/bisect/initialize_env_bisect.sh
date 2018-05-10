#!/bin/bash

set -x

function git_clone () {
    local kernel_tree="$1"; shift
    local folder_name="$1"; shift
    local git_branch="$1"; shift
    local remote="$1"

    pushd "$target"
        git clone $kernel_tree
        pushd "$folder_name"
        # because the repo is very large, we have to disable the git garbage
        # colector since it will start deleting objects
        git config --global gc.auto 0

        # we want to configure the remote ourselves in case we want to merge
        # code from forks
        git remote rename origin "$remote"

        git checkout -f "$remote/$git_branch"
        popd
    popd
}

function update_repo () {
    local kernel_tree="$1"; shift
    local folder_name="$1"; shift
    local git_branch="$1"; shift
    local remote="$1"

    pushd $folder_name
    # first we clean the git repo wherever we are
    git clean -x -f -d

    is_repo=$(git remote | grep "$remote" | wc -l)
    if [[ $is_repo -eq 0 ]]; then
        git remote add "$remote" "$kernel_tree"
    fi
    git fetch --all

    # we checkout to specified branch and pull the code
    git checkout -f "$remote/$git_branch"
    git pull "$remote" "$git_branch"
    # if there are any merge conflicts we have to reclone the repo
    if [[ $? -ne 0 ]]; then
        popd
        rm -rf "$folder_name"
        git_clone "$kernel_tree" "$folder_name" "$git_branch"
        return
    fi

    popd
}

function get_repo_folder () {
    local kernel_tree="$1"

    local folder
    folder=${kernel_tree##*/}
    folder=${folder%.*}
    echo "$folder"
}

function get_repo_remote () {
    local kernel_tree="$1"

    local remote
    remote=${kernel_tree%/*}
    remote=${remote##*/}
    echo "$remote"
}

function main () {
    local kernel_tree
    local build_dir
    local git_branch

    while true; do
        case "$1" in
            --kernel_tree)
                kernel_tree="$2"
                shift 2;;
            --build_dir)
                build_dir="$2"
                shift 2;;
            --git_branch)
                git_branch="$2"
                shift 2;;
            *) break ;;
        esac
    done

    dir=$(get_repo_folder "$kernel_tree")
    remote=$(get_repo_remote "$kernel_tree")

    mkdir -p "$build_dir"
    pushd "$build_dir"
    if [[ ! -d "$dir" ]]; then
        git_clone "$kernel_tree" "$dir" "$git_branch" "$remote"
    else
        update_repo "$kernel_tree" "$dir" "$git_branch" "$remote"
    fi
    popd
}

main "$@"
