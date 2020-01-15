#!/bin/bash
set -xe -o pipefail

BASEDIR=$(dirname $0)

function main {
    TEMP=$(getopt -o n:s:i:k:b --long job_id:,kernel_folder_path:,smb_share_url:,smb_share_username:,smb_share_password: -n 'get_kernel_folder.sh' -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    echo $TEMP

    eval set -- "$TEMP"
    while true ; do
        case "$1" in
            --job_id)
                case "$2" in
                    "") shift 2 ;;
                    *) JOB_ID="$2" ; shift 2 ;;
                esac ;;
            --kernel_folder_path)
                case "$2" in
                    "") shift 2 ;;
                    *) KERNEL_FOLDER_PATH="$2" ; shift 2 ;;
                esac ;;
            --smb_share_url)
                case "$2" in
                    "") shift 2 ;;
                    *) SMB_SHARE_URL="$2" ; shift 2 ;;
                esac ;;
            --smb_share_username)
                case "$2" in
                    "") shift 2 ;;
                    *) SMB_SHARE_USERNAME="$2" ; shift 2 ;;
                esac ;;
            --smb_share_password)
                case "$2" in
                    "") shift 2 ;;
                    *) SMB_SHARE_PASSWORD="$2" ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) echo "Wrong parameters!" ; exit 1 ;;
        esac
    done

    MOUNT_POINT="/tmp/${JOB_ID}"
    KERNEL_TRANSLATED_FOLDER_PATH="./${JOB_ID}/kernel_translated_folder"

    mkdir -p $MOUNT_POINT
    mkdir -p "./${JOB_ID}"
    sudo mount -t cifs "${SMB_SHARE_URL}" $MOUNT_POINT \
        -o vers=3.0,username=${SMB_SHARE_USERNAME},password=${SMB_SHARE_PASSWORD},dir_mode=0777,file_mode=0777,sec=ntlmssp

    if [[ ${KERNEL_FOLDER_PATH} == "latest" ]];then
        lines=$(ls -t $MOUNT_POINT | grep -iv "debug")
    else
        lines="${KERNEL_FOLDER_PATH}"
    fi
    found_deb=0

    for line in $lines; do
        if [[ -d "${MOUNT_POINT}/${line}/deb" && \
              -d "${MOUNT_POINT}/${line}/deb/meta_packages" ]]; then
             echo "$line has all the required files in it";
             echo "$line" > "${KERNEL_TRANSLATED_FOLDER_PATH}"
             mv -f "${BASEDIR}/deb" "${BASEDIR}/deb.bak" || true
             cp -r "${MOUNT_POINT}/${line}/deb" "${BASEDIR}/deb"
             found_deb=1
             break;
        fi
    done

    found_rpm=0
    for line in $lines; do
        if [[ -d "${MOUNT_POINT}/${line}/rpm" ]]; then
             echo "$line has all the required files in it";
             echo "$line" > "${KERNEL_TRANSLATED_FOLDER_PATH}"
             cp -r "${MOUNT_POINT}/${line}/rpm" "${BASEDIR}/rpm"
             found_rpm=1
             break;
        fi
    done

    sudo umount $MOUNT_POINT

    if [[ $found_deb == 0 ]] && [[ $found_rpm == 0 ]]; then
        echo "KERNEL folder $KERNEL_FOLDER_PATH does not meet the requirements."
        exit 1
    fi
}


main $@