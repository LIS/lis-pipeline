#!/bin/bash

function main(){
    BUILD_NUMBER="$1"
    RESOURCE_GROUP_NAME="kernel-validation"
    STORAGE_ACCOUNT_NAME="kernelstorageacc"

    az group deployment delete -n "$BUILD_NUMBER"-KernelBuild -g $RESOURCE_GROUP_NAME
    az vm delete -n "$BUILD_NUMBER"-Kernel-Validation -y -g $RESOURCE_GROUP_NAME
    az storage blob delete -c vhds -n "$BUILD_NUMBER"-osdisk.vhd --account-name $STORAGE_ACCOUNT_NAME
    az resource delete -n "$BUILD_NUMBER"-VMNic --resource-type "Microsoft.Network/networkInterfaces" -g $RESOURCE_GROUP_NAME
    az resource delete -n "$BUILD_NUMBER"-PublicIP --resource-type "Microsoft.Network/publicIPAddresses" -g $RESOURCE_GROUP_NAME
    az resource delete -n "$BUILD_NUMBER"-VNET --resource-type "Microsoft.Network/virtualNetworks" -g $RESOURCE_GROUP_NAME
}

main $@