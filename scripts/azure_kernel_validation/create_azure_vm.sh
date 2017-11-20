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
    vm_params=""

    params="$(split_string $params ,)"

    for param in $params;do
        value="${param#*=}"
        param="${param%%=*}"
        sed -i -e "s#<$param>#$value#g" ../../install_kernel.sh
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
    
    parse_vm_params $params
    
    git reset --hard HEAD
    sed -i -e "s/%number%/$build_number/g" ./azuredeploy.parameters.json
    sed -i -e "s/%params%/$(cat ../../install_kernel.sh | base64 -w 0)/g" ./azuredeploy.parameters.json
}

function create_vm(){
    deploy_data="$1"
    resource_group="$2"

    chmod +x ./az-group-deploy.sh
    ./az-group-deploy.sh -a "$deploy_data" -g "$resource_group" -l northeurope
}

function main(){
    CLONE_REPO="n"
    DEPLOY_DATA="azure_kernel_validation"
    RESOURCE_GROUP=""
    VM_PARAMS=""

    while true;do
        case "$1" in
            --clone_repo)
                CLONE_REPO="$2"
                shift 2;;
            --vm_params)
                VM_PARAMS="$2"
                shift 2;;
            --deploy_data)
                DEPLOY_DATA="$2"
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

    #install_deps
    #azure_login
    if [[ "$CLONE_REPO" == "y" ]];then
        if [[ -d "./azure-quickstart-templates" ]];then
            rm -rf "./azure-quickstart-templates"
        fi
        git clone https://github.com/mbivolan/azure-quickstart-templates.git
    fi
    echo "Azure image type used: $OS_TYPE"
    pushd "./azure-quickstart-templates"
    pushd "./$DEPLOY_DATA"
    change_vm_params "$VM_PARAMS" "$BUILD_NUMBER"
    popd
    create_vm "$DEPLOY_DATA" "$RESOURCE_GROUP"
    popd
}

main $@
