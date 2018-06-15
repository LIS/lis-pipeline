#!/bin/bash

set -xe

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
    os_type="$3"
    vm_params=""
    params_file=""
    
    params="$(split_string $params ,)"
    
    params_file="./azuredeploy.parameters.json"

    for param in $params;do
        value="${param#*=}"
        param="${param%%=*}"
        sed -i -e "s#<$param>#$value#g" "$params_file"
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
    build_number=$(echo "$2" | tr "[:upper:]" "[:lower:]")
    os_type="$3"
    base_dir="$4"
    flavor="$5"
    os_version="$6"
    resource_location="$7"
    storage_account_name="$8"
    
    parse_vm_params "$params" "$base_dir" "$os_type" "$resource_location"

    file="azuredeploy.parameters.json"
    ( jq ".parameters.buildNumber.value           = \"$build_number\""         $file > tmp ) && mv tmp $file
    ( jq ".parameters.flavor.value                = \"$flavor\""               $file > tmp ) && mv tmp $file
    ( jq ".parameters.location.value              = \"$resource_location\""    $file > tmp ) && mv tmp $file
    ( jq ".parameters.newStorageAccountName.value = \"$storage_account_name\"" $file > tmp ) && mv tmp $file

    if [[ "$os_version" != "" ]];then
        sed -i -e "s/%os_version%/$os_version/g" ./azuredeploy.parameters.json
    fi
}

function create_vm(){
    deploy_data="$1"
    resource_group="$2"
    build_number="$3"
    resource_location="$4"
    storage_account_name="$5"

    chmod +x ./az-group-deploy.sh
    ./az-group-deploy.sh -a "$deploy_data" -g "$resource_group" -l "$resource_location" -n "$build_number" -s "$storage_account_name"
}

function main(){
    RESOURCE_GROUP=""
    RESOURCE_LOCATION=""
    VM_PARAMS=""
    BASE_DIR="$(pwd)"
    TEMPLATE_FOLDER="${BASE_DIR}/azure_templates"
    OS_TYPE=""
    INSTALL_DEPS="n"
    FLAVOR="Standard_A2"
    OS_VERSION=""

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
            --os_type)
                OS_TYPE="$2"
                shift 2;;
            --os_version)
                OS_VERSION="$2"
                shift 2;;
            --build_number)
                BUILD_NUMBER="$2"
                shift 2;;
            --resource_location)
                RESOURCE_LOCATION="$2"
                shift 2;;
            --flavor)
                FLAVOR="$2"
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
            template_folder_temp="${TEMPLATE_FOLDER}/temp${OS_TYPE}${FLAVOR}"
            if [[ -d "${template_folder_temp}" ]];then
                rm -f "${template_folder_temp}/"*
            fi
            mkdir -p "${template_folder_temp}"
            cp "${TEMPLATE_FOLDER}/${OS_TYPE}_deploy/"* "${template_folder_temp}"
            TEMPLATE_FOLDER=${template_folder_temp}
        else
            echo "Cannot find templates for os type: $OS_TYPE"
            exit 1
        fi
    else
        exit 1
    fi

    storage_account_name="lspl$RESOURCE_LOCATION"
    echo "Azure image type used: $OS_TYPE"
    pushd "$TEMPLATE_FOLDER"
    change_vm_params "$VM_PARAMS" "$BUILD_NUMBER" "$OS_TYPE" "$BASE_DIR" "$FLAVOR" "$OS_VERSION" "$RESOURCE_LOCATION" "$storage_account_name"
    popd
    pushd "$BASE_DIR"
    create_vm "$TEMPLATE_FOLDER" "$RESOURCE_GROUP" "$BUILD_NUMBER" "$RESOURCE_LOCATION" "$storage_account_name"
    popd
}

main $@
