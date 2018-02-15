#!/bin/bash
set -xe

function main() {

    VM_NAME=""
    DESTINATION_PATH=""
    RESOURCE_GROUP="kernel-validation"
    
    while true;do
        case "$1" in
            --vm_name)
                VM_NAME="$2" 
                shift 2;;
            --destination_path)
                DESTINATION_PATH="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    if [[ "$VM_NAME" == "" ]] || [[ "$DESTINATION_PATH" == "" ]];then
        exit 1;
    fi
    if [[ -d "$DESTINATION_PATH" ]];then
        exit 1
    else
        mkdir -p "$DESTINATION_PATH"
    fi
    sleep 30
    az vm boot-diagnostics get-boot-log --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" > "$DESTINATION_PATH/boot_${VM_NAME}.log"
}

main $@
