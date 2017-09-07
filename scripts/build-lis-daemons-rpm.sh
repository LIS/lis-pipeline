#!/bin/bash

set -e

function prepare {
    if [[ -e "$HOME/.rpmmacros" ]];then
        mv "$HOME/.rpmmacros" "$HOME/.rpmmacros.old"
    fi
    cat << EOF > "$HOME/.rpmmacros"
%packager test
%_topdir ${BASE_DIR}/rpmbuild
%_tmppath ${BASE_DIR}/rpmbuild/tmp
EOF
    yum groups mark install "Development Tools"
    yum -y groupinstall "Development Tools"
    yum -y install rpm-build rpmdevtools yum-utils
    mkdir "${BASE_DIR}/base_pack"
    pushd "${BASE_DIR}/base_pack"
    yumdownloader --source hyperv-daemons
    rpm -ivh *.rpm
    popd
}

function get_source_kernel {
    pushd "$BASE_DIR"
    if [[ $URL ]];then
        mkdir linux-temp
        pushd "./linux-temp"
        wget $URL
        tar_File="$(find *tar*)"
        tar xf "$tar_File"
        source_Folder="${tar_File%.tar*}"
        SOURCE_PATH="$(readlink -e $source_Folder)"
        popd
    elif [[ $REPO ]];then
        mkdir linux-temp
        pushd "./linux-temp"
        git clone $REPO
        source_Folder="$(find *)"
        SOURCE_PATH="$(readlink -e $source_Folder)"
        if [[ $BRANCH ]];then
            pushd "$SOURCE_PATH"
            git checkout $BRANCH
            popd
        fi
        popd
    else
        SOURCE_PATH=$LOCAL
    fi
    popd
}

function configure {
    pushd "$SOURCE_PATH"
    VERSION="$(make kernelversion)"
    VERSION="${VERSION%-*}"
    popd
    pushd "${BASE_DIR}/rpmbuild/SPECS/"
    spec_Name="hyperv-daemons.spec"
    # Configure SPEC file with version...
    if [[ $VERSION ]];then
        sed -i -e "s/Version:.*/Version:  $VERSION/g" "${spec_Name}"
    fi
    sed -i -e "s/Release:.*/Release:  %{?dist}/g" "${spec_Name}"
    sed -i '/Patch/d' "${spec_Name}"
    sed -i '/%patch/d' "${spec_Name}"
    sed -i '/Requires:/d' "${spec_Name}"
    popd
}

function build {
    pushd "${BASE_DIR}/rpmbuild"
    if [[ ! -d "${SOURCE_PATH}/tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp "${SOURCE_PATH}/tools/hv"/*.c "./SOURCES"
        if [[ -e "${SOURCE_PATH}/tools/hv"/*.sh ]];then
            cp "${SOURCE_PATH}/tools/hv"/*.sh "./SOURCES"
        else
            printf "Using default hv_kvp scripts"
        fi
        if [[ -e "${SOURCE_PATH}/tools/hv"/*.rules ]];then
            cp "${SOURCE_PATH}/tools/hv"/*.rules "./SOURCES"
        else
            printf "Using default rules"
        fi
        if [[ -e "${SOURCE_PATH}/tools/hv"/lsvmbus ]];then
            cp "${SOURCE_PATH}/tools/hv"/lsvmbus "./SOURCES"
        fi
        if [[ -e "${SOURCE_PATH}/tools/hv/"*.spec ]];then
            $SPEC_PATH=`find "${SOURCE_PATH}/tools/hv/"*.spec`
            cp $SPEC_PATH "./SPECS"
        fi
    fi
    
    if [[ $SPEC_PATH != "" ]];then
        spec=${SPEC_PATH##*/}
        rpmbuild -ba "SPECS/$spec"
    else
        rpmbuild -ba "SPECS/hyperv-daemons.spec"
    fi
    if [[ $? -ne 0 ]];then
        printf "\n Something went wrong building rpms \n"
        exit 3
    fi
    if [[ -d "./RPMS/x86_64" ]];then
        cp ./RPMS/x86_64/*rpm "$DEST_FOLDER"
    fi
    popd
}

function clear_temps {
    if [[ "$CLEAR" == "OK" ]];then
        rm -Rf "$BASE_DIR"
    fi
    if [[ -e "${HOME}/.rpmmacros.old" ]];then
        rm -f "${HOME}/.rpmmacros"
        mv "${HOME}/.rpmmacros.old" "${HOME}/.rpmmacros"
    fi
}

function build_rpms {
    BASE_DIR="$(pwd)/temp-build/"
    DEST_FOLDER="$(pwd)/hyperv-rpms"
    REPO=""
    BRANCH=""
    URL=""
    LOCAL=""
    CLEAR=""
    SOURCE_PATH=""
    SPEC_PATH=""
    
    while getopts "u:r:l:c:b" opt; do
        case $opt in
            u)
                URL=$OPTARG ;;
            r)
                REPO=$OPTARG ;;
            l)
                LOCAL="$(readlink -e $OPTARG)" ;;
            c)
                CLEAR="OK" ;;
        esac
    done
    
    if [[ ! -d "$BASE_DIR" ]];then
        mkdir $BASE_DIR
    else 
        rm -Rf "${BASE_DIR}"/*
    fi
    if [[ ! $URL ]] && [[ ! $REPO ]] && [[ ! $LOCAL ]];then
        printf "\n\n You need to specify 1 way to get sources. \n\n"
        exit 3
    fi
    if [[ ! -d $DEST_FOLDER ]];then
        mkdir $DEST_FOLDER
    fi
    
    prepare
    get_source_kernel
    configure
    build
    clear_temps
}

build_rpms "$@"
