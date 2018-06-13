#!/bin/bash

set -x
set -e -o pipefail

function remove_log_container() {
    build_number="$1"
    storage_name="$2"
    resource_group_name="$3"
    
    if [[ "$build_number" == "" ]] || [[ "$storage_name" == "" ]] || [[ "$resource_group_name" == "" ]];then
        exit 1
    fi

    log_container="$(az storage container list --account-name $storage_name | grep name | grep $build_number)"
    log_container="${log_container#*:}"
    log_container="${log_container%\"*}"
    log_container="${log_container#*\"}"

    account_key="$(az storage account keys list --account-name $storage_name \
        --resource-group $resource_group_name | grep value | head -1)"
    account_key="${account_key#*:}"
    account_key="${account_key%\"*}"
    account_key="${account_key#*\"}"

    if [[ "$log_container" != "" ]] && [[ "$account_key" != "" ]];then
       az storage container delete --name "$log_container" --account-name "$storage_name" --account-key "$account_key"
    fi
}

function main(){
    BUILD_NUMBER="$1"
    RESOURCE_LOCATION="$2"
    RESOURCE_GROUP_NAME="kernel-validation"

    if [[ ! -z $RESOURCE_LOCATION ]]; then
        STORAGE_ACCOUNT_NAME="lspl$RESOURCE_LOCATION"
    else
        STORAGE_ACCOUNT_NAME="lsplwestus2"
    fi

    az group deployment delete -n "$BUILD_NUMBER"-KernelBuild -g $RESOURCE_GROUP_NAME
    az vm delete -n "$BUILD_NUMBER"-Kernel-Validation -y -g $RESOURCE_GROUP_NAME
    low_name="$(echo "$BUILD_NUMBER" | tr '[:upper:]' '[:lower:]')"
    az storage blob delete -c vhds -n "$low_name"-osdisk.vhd --account-name $STORAGE_ACCOUNT_NAME
    az resource delete -n "$BUILD_NUMBER"-VMNic --resource-type "Microsoft.Network/networkInterfaces" -g $RESOURCE_GROUP_NAME
    az resource delete -n "$BUILD_NUMBER"-PublicIP --resource-type "Microsoft.Network/publicIPAddresses" -g $RESOURCE_GROUP_NAME
    az resource delete -n "$BUILD_NUMBER"-VNET --resource-type "Microsoft.Network/virtualNetworks" -g $RESOURCE_GROUP_NAME
    logs_name="${low_name/-/}"
    remove_log_container "$logs_name" "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP_NAME"
}

main $@
