#!/bin/bash

set -xoe pipefail

ret_val() {
    while read val;do
        last_val="$val"
    done
    echo "$last_val"
}

run_remote_commands() {
    PRIVATE_KEY="$1"
    USERNAME="$2"
    REMOTE_IP="$3"
    COMMANDS="$4"

    IFS=';'; COMMANDS=($COMMANDS); unset IFS;
    for comm in "${COMMANDS[@]}"; do
        trimmed_com="$(echo $comm | xargs)"
        output="$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USERNAME@$REMOTE_IP" "$trimmed_com")"
        echo "$output"
    done
}

wait_for_ip() {
    FULL_BUILD_NAME="$1"
    RESOURCE_GROUP="$2"

    COUNTER=0
    INTERVAL=5
    AZURE_MAX_RETRIES=60

    while [ $COUNTER -lt $AZURE_MAX_RETRIES ]; do
        public_ip_raw=$(az network public-ip show --name "$FULL_BUILD_NAME-PublicIP" --resource-group kernel-validation --query '{address: ipAddress }')
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
    echo "$public_ip"
}

main() {
    WORKDIR="$(pwd)"
    BASEDIR="$WORKDIR/scripts/azure_kernel_validation"
    PRIVATE_KEY_PATH="${HOME}/azure_priv_key.pem"
    VM_USER_NAME="rhel"
    OS_TYPE="rhel"
    RESOURCE_GROUP="kernel-validation"
    RESOURCE_LOCATION="northeurope"
    FLAVOR="Standard_A2"
    
    while true;do
        case "$1" in
            --build_name)
                BUILD_NAME="$2" 
                shift 2;;
            --build_number)
                BUILD_NUMBER="$2" 
                shift 2;;
             --kernel_version)
                KERNEL_VERSION="$2" 
                shift 2;;
            --vm_user_name)
                VM_USER_NAME="$2"
                shift 2;;
            --os_type)
                OS_TYPE="$2"
                shift 2;;
            --lis_link)
                LIS_LINK="$2"
                shift 2;;
            --resource_group)
                RESOURCE_GROUP="$2"
                shift 2;;
            --resource_location)
                RESOURCE_LOCATION="$2"
                shift 2;;
            --flavor)
                FLAVOR="$2"
                shift 2;;
            --log_destination)
                LOG_DEST="$(readlink "$2")"
                shift 2;;
            *) break ;;
        esac
    done
    
    pushd "$BASEDIR"
    
    IFS='_'; OS_TYPE=($OS_TYPE); unset IFS;
    OS_VERSION="${OS_TYPE[1]}"
    OS_TYPE="${OS_TYPE[0]}"

    # Create azure vm
    FULL_BUILD_NAME="$BUILD_NAME$BUILD_NUMBER"
    bash create_azure_vm.sh --build_number "$FULL_BUILD_NAME" \
        --resource_group $RESOURCE_GROUP --os_type $OS_TYPE --os_version $OS_VERSION
        --resource_location $RESOURCE_LOCATION --flavor $FLAVOUR
    PUBLIC_IP="$(wait_for_ip $FULL_BUILD_NAME $RESOURCE_GROUP | ret_val)"
    
    # Install the desired kernel version
    run_remote_commands "$PRIVATE_KEY_PATH" "$VM_USER_NAME" "PUBLIC_IP" \
        "yum -y update;
         yum -y install wget;
         yum -y install kernel-${KERNEL_VERSION};
         reboot"
    PUBLIC_IP="$(wait_for_ip $FULL_BUILD_NAME $RESOURCE_GROUP | ret_val)"
    installed_version="$(run_remote_commands "$PRIVATE_KEY_PATH" "$VM_USER_NAME" "PUBLIC_IP" "uname -r" | ret_val)"
    if [[ "$KERNEL_VERSION" != "*installed_version*" ]];then
        exit 1
    fi
    
    # Install LIS
    run_remote_commands "$PRIVATE_KEY_PATH" "$VM_USER_NAME" "PUBLIC_IP" \ 
         "wget ${lis_link} -O lis_package.rpm;
         rpm -ivh lis_package.rpm;
         reboot" > "${LOG_DEST}\lis_install_result"
    popd
}