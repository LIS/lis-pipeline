#!/bin/bash

set -xe

get_lis_os() {
    os_type="$1"
    os_version="$2"
    
    os_type="$(echo "$os_type" | tr /a-z/ /A-Z/)"
    os_version=${os_version//.}
    echo "${os_type}${os_version}"
}

run_remote_az_commands() {
    set +xe
    RESOURCE_GROUP="$1"
    VM_NAME="$2"
    OUTPUT="$3"
    COMMANDS="$4"
    PARAMS="$5"
    
    TIMEOUT=600
    
    IFS=';'; COMMANDS=($COMMANDS); unset IFS;
    for comm in "${COMMANDS[@]}"; do
        trimmed_com="$(echo $comm | xargs)"
        COMM_STATUS=124
        while [ $COMM_STATUS -eq 124 ]; do
            output="$(timeout $TIMEOUT az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME \
                            --command-id RunShellScript --scripts "$comm" --parameters $PARAMS 2>&1)"
            COMM_STATUS=$?
        done
        if [ $COMM_STATUS -ne 0 ];then
            printf "$output"
            break
        else
            output="$(echo $output | jq '.value[].message')"
            trimmed_output="$(echo $output | tr -d '"')"
            full_output="[stdout]${trimmed_output#*stdout]}"
            std_output="${trimmed_output#*stdout]\\n}"
            std_output="${std_output%\\n[stderr*}"
            if [[ "$OUTPUT" == "full_output" ]];then
                printf "$full_output"
            elif [[ "$OUTPUT" == "std_output" ]];then
                printf "$std_output"
            fi
        fi
    done
    set -xe
    return $COMM_STATUS
}

main() {
    BASEDIR="$(dirname $0)"
    OS_TYPE="rhel"
    RESOURCE_GROUP="kernel-validation"
    RESOURCE_LOCATION="westus2"
    FLAVOR="Standard_A2"
    AZURE_CORE_COLLECT_TELEMETRY=false
    
    while true;do
        case "$1" in
            --workdir)
                WORK_DIR="$2"
                shift 2;;
            --build_name)
                BUILD_NAME="$2" 
                shift 2;;
            --build_number)
                BUILD_NUMBER="$2" 
                shift 2;;
            --kernel_version)
                KERNEL_VERSION="$2" 
                shift 2;;
            --rhel_username)
                USERNAME="$2"
                shift 2;;
            --rhel_password)
                PASSWORD="$2"
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
                LOG_DEST="$(readlink -f "$2")"
                shift 2;;
            --sku)
                AZURE_SKU="$2"
                shift 2;;
            --azure_token)
                AZURE_TOKEN="$2"
                shift 2;;
            *) break ;;
        esac
    done

    AZUREDIR="$WORKSPACE/$WORK_DIR/scripts/azure_kernel_validation"
    
    if [[ ! -d "$LOG_DEST" ]];then
        mkdir "$LOG_DEST"
    fi
    
    pushd "$AZUREDIR"
    IFS='_'; OS_TYPE=($OS_TYPE); unset IFS;
    OS_VERSION="${OS_TYPE[1]}"
    OS_TYPE="${OS_TYPE[0]}"
    
    if [[ "$AZURE_SKU" == "" ]];then
        AZURE_SKU="$OS_VERSION"
    fi
    # Create azure vm
    FULL_BUILD_NAME="$BUILD_NAME$BUILD_NUMBER"
    bash create_azure_vm.sh --build_number "$FULL_BUILD_NAME" \
        --resource_group $RESOURCE_GROUP --os_type $OS_TYPE --os_version $AZURE_SKU \
        --resource_location $RESOURCE_LOCATION --flavor $FLAVOR
        
    FULL_VM_NAME="${FULL_BUILD_NAME}-Kernel-Validation"
    popd
    
    pushd $BASEDIR
    # Install the desired kernel version
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "full_output" \
        "@prepare_lis_vm.sh" \
        "sec=install_kernel os_ver=\"$OS_VERSION\" workdir=\"/root/\" \
            kernel_ver=\"$KERNEL_VERSION\" rhel_user=\"$USERNAME\" rhel_pass=\"$PASSWORD\""
    
    # Reboot vm
    az vm restart --resource-group "$RESOURCE_GROUP" --name "$FULL_VM_NAME"
    
    # Download LIS
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "std_output" \
        "wget ${LIS_LINK}'${AZURE_TOKEN}' -O /root/lis_package.tar.gz &&
        tar -xzvf /root/lis_package.tar.gz -C /root/;" "param=none"
    
    # Install LIS
    echo "LIS modules install:" > "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_install.log"
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "full_output" \
        "@prepare_lis_vm.sh" \
        "sec=install_lis workdir=\"/root/\" kernel_ver=\"$KERNEL_VERSION\" os_ver=\"$OS_VERSION\" lis_path=\"/root/LISISO\"" \
        >> "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_install.log"

    # Reboot vm
    az vm restart --resource-group "$RESOURCE_GROUP" --name "$FULL_VM_NAME"
    
    echo "Distro: ${OS_TYPE}_${OS_VERSION}" \
        > "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_check.log"
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "std_output" \
        "@check_lis_modules.sh" "os_ver=\"$OS_VERSION\"" >> "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_check.log"
    popd
}

main $@
