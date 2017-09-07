#!/bin/bash

set -e

function prepare {
    apt-get -y install devscripts build-essential lintian debhelper git
    pushd "$BASE_DIR"
    mkdir -p hyperv-daemons/debian
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

function get_deps {
    mkdir "${BASE_DIR}/base_pack"
    pushd "${BASE_DIR}/base_pack"
    sed -i 's/^# deb-src /deb-src /g' /etc/apt/sources.list
    apt-get update
    apt-get source linux-cloud-tools-common
    for i in *;do
        if [[ -d $i ]];then
            DEPEND_PATH=$(readlink -e $i)
        fi
    done
    popd
    mkdir "${BASE_DIR}/dependencies"
    pushd "${BASE_DIR}/dependencies"
    apt-get download linux-cloud-tools-common
    dpkg-deb -R *.deb .
    popd
}
    
function create_source_pack {
    pushd "$SOURCE_PATH"
    kernel_ver="$(make kernelversion)"
    kernel_ver="${kernel_ver%-*}"
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp ./tools/hv/* "${BASE_DIR}/hyperv-daemons"
        sed -i "s#\.\./\.\.#'${SOURCE_PATH}'#g" "${BASE_DIR}/hyperv-daemons/Makefile"
    fi
    popd
    pushd "${BASE_DIR}/hyperv-daemons"
    dch --create --distribution unstable --package "hyperv-daemons" --newversion "$kernel_ver" "First Build"
    for i in *.sh;do
        mv "$i" "${i%.*}"
    done
    pushd "./debian"
    cat << EOF > control
Source: hyperv-daemons
Maintainer: test <test@mail.com>
Build-Depends: debhelper (>= 8.0.0)
Standards-Version: $kernel_ver
Section: utils

Package: hyperv-daemons  
Priority: extra  
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}  
Description: Installs hv_kvp_daemon hv_fcopy_daemon hv_vss_daemon
EOF
    cat << EOF > copyright
Copyright 2017
EOF
    echo 9 > compat
    echo '#!/usr/bin/make -f' > rules  
    echo '%:' >> rules  
	echo '	dh $@' >> rules
    echo '' >> rules
    
    cat << EOF > install
hv_kvp_daemon /usr/sbin
hv_vss_daemon /usr/sbin
hv_fcopy_daemon /usr/sbin
hv_get_dhcp_info /usr/libexec/hypervkvpd
hv_get_dns_info /usr/libexec/hypervkvpd
hv_set_ifconfig /usr/libexec/hypervkvpd
EOF
    if [ $TARGET_OS_VERSION -ge 15 ];then
        for i in "${DEPEND_PATH}"/debian/*.service;do
            tem="${i##*/}"
            cp $i ./"${tem#*.}"
        done
        cat << EOF >> install
debian/hv-kvp-daemon.service /etc/systemd/system
debian/hv-vss-daemon.service /etc/systemd/system
debian/hv-fcopy-daemon.service /etc/systemd/system
EOF

        cat << EOF > preinst
#!/bin/bash

if [[ -e /etc/systemd/system/hv-kvp-daemon.service ]];then
    rm -f /etc/systemd/system/hv-kvp-daemon.service
fi
if [[ -e /etc/systemd/system/hv-vss-daemon.service ]];then
    rm -f /etc/systemd/system/hv-vss-daemon.service
fi
if [[ -e /etc/systemd/system/hv-fcopy-daemon.service ]];then
    rm -f /etc/systemd/system/hv-fcopy-daemon.service
fi     
EOF
        cp "${BASE_DIR}/dependencies/DEBIAN/postinst" .
        cp "${BASE_DIR}/dependencies/DEBIAN/postrm" .
        cp "${BASE_DIR}/dependencies/DEBIAN/prerm" .
    else 
        for i in "${DEPEND_PATH}"/debian/*.upstart;do
            tem="${i##*/}"
            cp $i ./"${tem#*.}"
            rename 's/upstart/conf/' *.upstart
        done
        cat << EOF >> install
debian/hv-kvp-daemon.conf /etc/init/
debian/hv-vss-daemon.conf /etc/init/
debian/hv-fcopy-daemon.conf /etc/init/
EOF
        cp "${BASE_DIR}/dependencies/DEBIAN/postinst" .
    fi
    popd
    popd
}

function build {
    pushd "${BASE_DIR}/hyperv-daemons"
    debuild -us -uc
    if [[ $? -ne 0 ]];then
        printf "Something went wrong building the deb"
        exit 3
    fi
    popd
    pushd "$BASE_DIR"
    cp *.deb "$DEST_FOLDER"
    popd
}

function clear_temps {
    if [[ $CLEAR == "OK" ]];then
        rm -Rf "$BASE_DIR"
    fi  
}

function build_debs {
    BASE_DIR="$(pwd)/temp-build"
    DEST_FOLDER="$(pwd)/hyperv-debs"
    DEPEND_PATH=""
    REPO=""
    BRANCH=""
    URL=""
    LOCAL=""
    CLEAR=""
    SOURCE_PATH=""
    TARGET_OS_VERSION=""
    
    while getopts "u:r:l:c:v:d" opt; do
        case $opt in
            u)
                URL=$OPTARG ;;
            r)
                REPO=$OPTARG ;;
            l)
                LOCAL="$(readlink -e $OPTARG)" ;;
            c)
                CLEAR="OK" ;;
            v)
                TARGET_OS_VERSION="${OPTARG%.*}" ;;
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
    if [[ ! $TARGET_OS_VERSION ]];then
        . /etc/lsb-release
        TARGET_OS_VERSION="${DISTRIB_RELEASE%.*}"
    fi
    prepare
    get_source_kernel
    get_deps
    create_source_pack
    build
    clear_temps
}

build_debs "$@"
