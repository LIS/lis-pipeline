#!/bin/bash

set -xe

RESOURCE_GROUP="kernel-validation"

validate_azure_vm_boot() {
    BASEDIR=$1
    BUILD_NAME=$2
    BUILD_NUMBER=$3
    USERNAME=$4
    PASSWORD=$5
    SMB_SHARE_URL=$6
    PRIVATE_KEY_PATH=$7
    VM_USER_NAME=$8

    KERNEL_VERSION_FILE="./kernel_version${BUILD_NUMBER}/scripts/package_building/kernel_versions.ini"
    KERNEL_FOLDER=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT folder)
    DESIRED_KERNEL_VERSION=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT version)
    DESIRED_KERNEL_TAG=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT git_tag)

    pushd "$BASEDIR"
    bash create_azure_vm.sh --build_number "$BUILD_NAME$BUILD_NUMBER" \
        --vm_params "username=$USERNAME,password=$PASSWORD,samba_path=$SMB_SHARE_URL/temp-kernel-artifacts,kernel_path=$KERNEL_FOLDER" \
        --resource_group $RESOURCE_GROUP --os_type $OS_TYPE
    popd

    INTERVAL=5
    COUNTER=0
    while [ $COUNTER -lt $AZURE_MAX_RETRIES ]; do
        public_ip_raw=$(az network public-ip show --name "$BUILD_NAME$BUILD_NUMBER-PublicIP" --resource-group kernel-validation --query '{address: ipAddress }')
        public_ip=$(echo $public_ip_raw | awk '{if (NR == 1) {print $3}}' | tr -d '"')
        if [ !  -z $public_ip ]; then
            echo "Public ip available: $public_ip."
            break
        else
            echo "Public ip not available."
        fi
        let COUNTER=COUNTER+1
    
        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    
    if [ $COUNTER -eq $AZURE_MAX_RETRIES ]; then
        echo "Failed to get public ip. Exiting..."
        exit 2
    fi

    MOUNT_POINT="/tmp/${BUILD_NUMBER}"
    DESTINATION_FOLDER=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT folder)
    mkdir -p $MOUNT_POINT
    sudo mount -t cifs "${SMB_SHARE_URL}/temp-kernel-artifacts" $MOUNT_POINT \
               -o vers=3.0,username=${USERNAME},password=${PASSWORD},dir_mode=0777,file_mode=0777,sec=ntlmssp
    scp -i $PRIVATE_KEY_PATH -r -o StrictHostKeyChecking=no "${MOUNT_POINT}/${KERNEL_FOLDER}/rpm" "$VM_USER_NAME@$public_ip:/tmp/"
    ssh -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$VM_USER_NAME@$public_ip" 'sudo rpm -ivh /tmp/rpm/kernel-*.rpm --nodeps --force'
    ssh -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$VM_USER_NAME@$public_ip" 'sudo sed -i s%GRUB_DEFAULT=.*%GRUB_DEFAULT=0% /etc/default/grub && sudo /sbin/grub2-mkconfig -o /boot/grub2/grub.cfg'
    ssh -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$VM_USER_NAME@$public_ip" 'sudo reboot' || true
    sudo umount $MOUNT_POINT

    sleep 10

    INTERVAL=5
    COUNTER=0
    while [ $COUNTER -lt $AZURE_MAX_RETRIES ]; do
        KERNEL_NAME=$(ssh -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$VM_USER_NAME@$public_ip" uname -r || true)
        if [[ "$KERNEL_NAME" == *"$DESIRED_KERNEL_TAG"* ]]; then
            echo "Kernel ${KERNEL_NAME} matched."
            exit 0
        else
            echo "Kernel $KERNEL_NAME does not match with desired Kernel tag: $DESIRED_KERNEL_TAG"
        fi
        let COUNTER=COUNTER+1
    
        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    exit 1
}

main() {
    BASEDIR=$(dirname $0)
    PRIVATE_KEY_PATH="${HOME}/azure_priv_key.pem"
    VM_USER_NAME="ubuntu"

    while true;do
        case "$1" in
            --build_name)
                BUILD_NAME="$2" 
                shift 2;;
            --build_number)
                BUILD_NUMBER="$2" 
                shift 2;;
            --sbm_share_username)
                USERNAME="$2" 
                shift 2;;
            --smb_share_password)
                PASSWORD="$2" 
                shift 2;;
            --smb_share_url)
                SMB_SHARE_URL="$2" 
                shift 2;;
            --private_key_path)
                PRIVATE_KEY_PATH="$2"
                shift 2;;
            --vm_user_name)
                VM_USER_NAME="$2"
                shift 2;;
            *) break ;;
        esac
    done

    validate_azure_vm_boot $BASEDIR $BUILD_NAME $BUILD_NUMBER $USERNAME \
        $PASSWORD $SMB_SHARE_URL $PRIVATE_KEY_PATH $VM_USER_NAME
}
main $@

