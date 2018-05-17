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
    
    IFS=';'; COMMANDS=($COMMANDS); unset IFS;
    for comm in "${COMMANDS[@]}"; do
        trimmed_com="$(echo $comm | xargs)"
        output="$(az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME \
                      --command-id RunShellScript --scripts "$trimmed_com" 2>&1)"
        COMM_STATUS=$?
        if [ $COMM_STATUS -ne 0 ];then
            printf "$output"
            break
        else
            output="$(echo $output | jq '.output[].message')"
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
    
    az vm run-command invoke -g "$RESOURCE_GROUP" -n "$FULL_VM_NAME" \
        --command-id RunShellScript \
        --scripts "sudo subscription-manager register --force \
                    --username ${USERNAME} --password ${PASSWORD}"
    
    # Install the desired kernel version
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "full_output" \
        "subscription-manager attach --auto;
         subscription-manager release --set=${OS_VERSION};
         subscription-manager repos --enable=rhel-7-server-eus-rpms;
         yum clean all;
         sudo yum -y install kernel-${KERNEL_VERSION};
         sudo yum -y install kernel-devel-${KERNEL_VERSION};"
    
    # Reboot vm
    az vm restart --resource-group "$RESOURCE_GROUP" --name "$FULL_VM_NAME"
    
    LIS_DISTRO="$(get_lis_os $OS_TYPE $OS_VERSION)"
    
    # Download LIS
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "std_output" \
        "sudo yum -y install wget gcc;
         wget ${LIS_LINK} -O ~/lis_package.tar.gz;
         tar -xzvf ~/lis_package.tar.gz -C ~/;
         cd ~ && rpm2cpio ./LISISO/${LIS_DISTRO}/*.src.rpm | cpio -idmv && tar -xf lis-next*;"
    
    # Install LIS
    echo "LIS Install Log:" > "${LOG_DEST}/lis_install.log"
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "full_output" \
        "cd ~/hv && bash ./*hv-driver-install;" >> "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_install.log"
          
    az vm restart --resource-group "$RESOURCE_GROUP" --name "$FULL_VM_NAME"
    
    pushd $BASEDIR
    echo "LIS modules check for ${OS_TYPE}_${OS_VERSION} with kernel ${KERNEL_VERSION}:" \
        > "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_check.log"
    run_remote_az_commands "$RESOURCE_GROUP" "$FULL_VM_NAME" "std_output" \
        "@check_lis_modules.sh" >> "${LOG_DEST}/${OS_TYPE}_${OS_VERSION}_lis_check.log"
    popd
}

main $@