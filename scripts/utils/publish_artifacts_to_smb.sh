#!/bin/bash
set -xe

function main(){
    SMB_SHARE_URL=""
    USERNAME=""
    PASSWORD=""
    FOLDER_PREFIX=""
    BUILD_NUMBER=""
    KERNEL_ARTIFACTS_PATH=""
    
    while true;do
        case "$1" in
            --smb_url)
                SMB_SHARE_URL="$2" 
                shift 2;;
            --smb_username)
                USERNAME="$2"
                shift 2;;
            --smb_password)
                PASSWORD="$2"
                shift 2;;
            --build_number)
                BUILD_NUMBER="$2"
                shift 2;;
            --artifacts_path)
                KERNEL_ARTIFACTS_PATH="$2"
                shift 2;;
            --artifacts_folder_prefix)
                FOLDER_PREFIX="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    MOUNT_POINT="/tmp/${BUILD_NUMBER}"
    mkdir -p $MOUNT_POINT
    sudo mount -t cifs "${SMB_SHARE_URL}" $MOUNT_POINT \
        -o vers=3.0,username=${USERNAME},password=${PASSWORD},dir_mode=0777,file_mode=0777,sec=ntlmssp
    JOB_KERNEL_ARTIFACTS_PATH="${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
    relpath_kernel_artifacts=$(realpath "scripts/package_building/${JOB_KERNEL_ARTIFACTS_PATH}")
    sudo cp -rf "${relpath_kernel_artifacts}/${FOLDER_PREFIX}"* $MOUNT_POINT
    rm -rf "${relpath_kernel_artifacts}"
    sudo umount $MOUNT_POINT
}

main $@
