#!/bin/bash

function split_string() {
    string="$1"
    del="$2"

    while test "${string#*$del}" != "$string" ; do
        split_str="${split_str} ${string%%$del*}"
        string="${string#*$del}"
    done
    split_str="${split_str# *} ${string}"
    echo "$split_str"
}

function parse_vm_params() {
    params="$1"
    base_dir="$2"
    vm_params=""

    params="$(split_string $params ,)"

    for param in $params;do
        value="${param#*=}"
        param="${param%%=*}"
        sed -i -e "s#<$param>#$value#g" "${base_dir}/install_kernel_${os_type}.sh"
    done
}

function install_deps(){
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ wheezy main" | \
        sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
    sudo apt-get -y install apt-transport-https git
    sudo apt-get -y update && sudo apt-get -y install azure-cli
}

function azure_login(){
    echo "No OP"
}

function change_vm_params(){
    params="$1"
    build_number="$2"
    os_type="$3"
    base_dir="$4"
    
    parse_vm_params "$params" "$base_dir"
    
    sed -i -e "s/%number%/$build_number/g" ./azuredeploy.parameters.json
    sed -i -e "s/%params%/$(cat ${base_dir}/install_kernel_${os_type}.sh | base64 -w 0)/g" ./azuredeploy.parameters.json
}

function create_vm(){
    deploy_data="$1"
    resource_group="$2"
    build_number="$3"

    chmod +x ./az-group-deploy.sh
    ./az-group-deploy.sh -a "$deploy_data" -g "$resource_group" -l northeurope -n "$build_number"
}

function main(){
    RESOURCE_GROUP=""
    VM_PARAMS=""
    TEMPLATE_FOLDER="$WORKSPACE/scripts/azure_templates"
    BASE_DIR="$(pwd)"
    OS_TYPE=""

    while true;do
        case "$1" in
            --install_deps)
                INSTALL_DEPS="$2"
                shift 2;;
            --vm_params)
                VM_PARAMS="$2"
                shift 2;;
            --resource_group)
                RESOURCE_GROUP="$2"
                shift 2;;
            --build_number)
                BUILD_NUMBER="$2"
                shift 2;;
            --os_type)
                OS_TYPE="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ "$INSTALL_DEPS" == "y" ]];then
        install_deps
    fi
    if [[ "$OS_TYPE" != "" ]];then
        if [[ -d "${TEMPLATE_FOLDER}/${OS_TYPE}_deploy" ]];then
            if [[ -d "${TEMPLATE_FOLDER}/temp" ]];then
                rm -rf "${TEMPLATE_FOLDER}/temp"
            fi
            mkdir "${TEMPLATE_FOLDER}/temp"
            cp "${TEMPLATE_FOLDER}/${OS_TYPE}_deploy/"* "${TEMPLATE_FOLDER}/temp"
            TEMPLATE_FOLDER="${TEMPLATE_FOLDER}/temp"
        else
            echo "Cannot find templates for os type: $OS_TYPE"
            exit 1
        fi
    else
        exit 1
    fi

    echo "Azure image type used: $OS_TYPE"
    pushd "./$TEMPLATE_FOLDER"
    change_vm_params "$VM_PARAMS" "$BUILD_NUMBER" "$OS_TYPE"
    popd
    pushd "./BASE_DIR"
    create_vm "$TEMPLATE_FOLDER" "$RESOURCE_GROUP" "$BUILD_NUMBER"
    popd
}

main $@
