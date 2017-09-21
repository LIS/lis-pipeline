#!/bin/bash

set -xe

. utils.sh

function install_deps_rhel {
    #
    # Installing packages required for the build process.
    #
    rpm_packages=(rpm-build rpmdevtools yum-utils ncurses-devel hmaccalc zlib-devel \ 
    binutils-devel elfutils-libelf-devel openssl-devel wget git ccache bc fakeroot)
    sudo yum groups mark install "Development Tools"
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install ${rpm_packages[@]}
}

function install_deps_debian {
    #
    # Installing packages required for the build process.
    #
    deb_packages=(libncurses5-dev xz-utils libssl-dev bc ccache kernel-package \
    devscripts build-essential lintian debhelper git wget bc fakeroot)
    DEBIAN_FRONTEND=noninteractive apt-get -y install ${deb_packages[@]}
}

function prepare_env_debian (){
    #
    # Prepare environment for build process (Debian, Ubuntu)
    #
    base_dir="$1"
    build_state="$2"
    
    pushd "$base_dir"
    if [[ $build_state == "daemons" ]];then
        rm -rf ./${build_state}
        mkdir -p ./${build_state}/hyperv-daemons/debian
    else
        mkdir -p ./${build_state}
    fi  
    popd
}

function prepare_env_rhel (){
    #
    # Prepare environment for the build process (CentOS, RHEL)
    #
    base_dir="$1"
    build_state="$2"
    
    pushd "$base_dir"
    cat << EOF > "$HOME/.rpmmacros"
%packager test
%_topdir ${base_dir}/${build_state}/rpmbuild
%_tmppath ${base_dir}/${build_state}/rpmbuild/tmp
EOF

    if [[ $build_state == "daemons" ]];then
        rm -rf ./${build_state}
    fi
    mkdir -p ./${build_state}
    popd
}

function get_sources_http (){
    #
    # Downloading kernel sources from http using wget
    #
    base_dir="$1"
    source_path="$2"
    
    pushd "${base_dir}/kernel"
    wget $source_path
    tarBall="$(ls *tar*)"
    tar xf $tarBall
    popd
    echo "${base_dir}/kernel/${tarBall%.tar*}"
}

function get_sources_git (){
    #
    # Downloading kernel sources from git
    #
    base_dir="$1"
    source_path="$2"
    git_branch="$3"
    git_folder_git_extension=${source_path##*/}
    git_folder=${git_folder_git_extension%%.*}
    source="${base_dir}/kernel/${git_folder}"

    pushd "${base_dir}/kernel"
    if [[ ! -d "${source}" ]];then
        git clone "$source_path" > /dev/null
    fi
    pushd "${source}"
    git reset --hard > /dev/null
    git fetch > /dev/null
    git checkout "$git_branch" > /dev/null
    popd
    popd
    echo "$source"
}

function get_sources_local (){
    #
    # Copy sources from local path
    #
    base_dir="$1"
    source_path="$2"
    
    pushd "${base_dir}/kernel"
    cp -rf "$source_path" .
    popd
    echo "${base_dir}/kernel/$(ls)"
}

function prepare_kernel_debian (){
    #
    # Make kernel config file 
    #
    source="$1"
    
    pushd "${source}"
    make olddefconfig
    touch REPORTING-BUGS
    popd
}

function prepare_kernel_rhel (){
    #
    # Make kernel cofig file
    #
    source="$1"
    
    pushd "${source}"
    make olddefconfig
    sed -i -e "s/%changelog*/ /g" "${source}/tools/hv/lis-daemon.spec"
    popd
}

function prepare_daemons_debian (){
    #
    # Copy daemons sources and dependency files for deb packet build process
    #
    base_dir="$1"
    source="$2"
    debian_version="$3"
    dep_path="$4"
    
    pushd "${source}"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    # Copy daemons sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp ./tools/hv/* "${base_dir}/daemons/hyperv-daemons"
        sed -i "s#\.\./\.\.#'${source}'#g" "${base_dir}/daemons/hyperv-daemons/Makefile"
    fi
    popd
    pushd "${base_dir}/daemons/hyperv-daemons"
    dch --create --distribution unstable --package "hyperv-daemons" \
        --newversion "$kernel_version" "jenkins"
    for i in *.sh;do
        mv "$i" "${i%.*}"
    done
    if [ ${debian_version} -ge 15 ];then
        cp "${dep_path}/16/"* "./debian"
    else
        cp "${dep_path}/14/"* "./debian"
    fi
    popd
}

function prepare_daemons_rhel (){
    #
    # Copy daemons sources and dependency files for rpm packet build process
    #
    base_dir="$1"
    source="$2"
    
    pushd "${base_dir}/daemons"
    yumdownloader --source hyperv-daemons
    rpm -ivh *.rpm
    popd
    pushd "${source}"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    # Copy daemons sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp -f ./tools/hv/* "${base_dir}/daemons/rpmbuild/SOURCES"
        sed -i "s#\.\./\.\.#'${source}'#g" "${base_dir}/daemons/rpmbuild/SOURCES/Makefile"
    fi
    popd
    pushd "${base_dir}/daemons/rpmbuild"
    if [[ -e "SOURCES/"*.spec ]];then
        spec="$(ls SOURCES/*.spec)"
        spec="${spec##*/}"
        mv -f "SOURCE/${spec}" "SPECS/${spec}"
    else
        sed -i -e "s/Version:.*/Version:  $kernel_version/g" "SPECS/hyperv-daemons.spec"
        sed -i -e "s/Release:.*/Release:  %{?dist}/g" "SPECS/hyperv-daemons.spec"
        sed -i '/Patch/d' "SPECS/hyperv-daemons.spec"
        sed -i '/%patch/d' "SPECS/hyperv-daemons.spec"
        sed -i '/Requires:/d' "SPECS/hyperv-daemons.spec"
        spec="$(ls SPECS/*.spec)"
        spec="${spec##*/}"
    fi
    popd
}

function build_debian (){
    #
    # Building the kernel or daemons for deb based OSs
    #
    base_dir="$1"
    source="$2"
    build_state="$3"
    thread_number="$4"
    destination_path="$5"
    
    if [[ "$build_state" == "kernel" ]];then
        pushd "$source"
        make-kpkg --initrd kernel_image kernel_headers -j"${thread_number}"
        popd
    else
        pushd "${base_dir}/daemons/hyperv-daemons"
        debuild -us -uc
        popd
    fi
    cp "${base_dir}/${build_state}/"*.deb "$destination_path"
}

function build_rhel {
    #
    # Building the kernel or daemons for rpm based OSs
    #
    base_dir="$1"
    source="$2"
    build_state="$3"
    thread_number="$4"
    destination_path="$5"
    spec="$6"

    if [[ "$build_state" == "kernel" ]];then
        pushd "$source"
        make rpm -j"${thread_number}"
        popd
    else
        pushd "${base_dir}/daemons/rpmbuild"
        rpmbuild -ba "SPECS/$spec"
        popd
    fi
    cp "${base_dir}/${build_state}/rpmbuild/RPMS/x86_64/"*.rpm "$destination_path"
}

function build_kernel (){
    #
    # Build the kernel
    #
    base_dir="$1"
    source_path="$2"
    os_family="$3"
    download_method="$4"
    destination_path="$5"
    thread_number="$6"
    build_state="kernel"
    git_branch="$7"

    prepare_env_"${os_family}" "$base_dir" "$build_state"
    source="$(get_sources_${download_method} $base_dir $source_path $git_branch)"
    prepare_kernel_"${os_family}" "$source"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$destination_path"
}

function build_daemons (){
    #
    # Build the daemons
    #
    base_dir="$1"
    source_path="$2"
    os_family="$3"
    download_method="$4"
    debian_version="$5"
    destination_path="$6"
    dep_path="$7"
    build_state="daemons"

    prepare_env_"${os_family}" "$base_dir" "$build_state"
    prepare_daemons_"${os_family}" "$base_dir" "$source" "$debian_version" "$dep_path"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$destination_path" "$spec"
}

function clean_env_debian (){
    #
    # Removing sources and files required by the build process.
    #
    base_dir="$1"
    
    rm -rf "${BASE_DIR}/"*
}

function clean_env_rhel (){
    #
    # Removing sources and files required by the build process.
    #
    base_dir="$1"
    
    rm -rf "${BASE_DIR}/"*
    rm -r "$HOME/.rpmmacros"
}

function main {
    os_info="$(get_os_version)"
    #Ex : os_info="os_VENDOR=Ubuntu os_RELEASE=16.04 os_UPDATE=4 os_PACKAGE=deb os_PACKAGE_MANAGER=apt os_CODENAME=xenial"
    for info in $os_info;do
        var_name="${info%=*}"
        var_value="${info#*=}"
        declare $var_name="$var_value"
    done
    
    BASE_DIR="$(pwd)/temp_build"
    DEP_PATH="$(pwd)/deps-lis/${os_PACKAGE}"
    USE_CCACHE="False"
    GIT_BRANCH="master"
    CLEAN_ENV="False"
    DOWNLOAD_METHOD=""
    THREAD_NUMBER="2"
    INSTALL_DEPS="True"
    DEBIAN_OS_VERSION="${os_RELEASE%.*}"
    
    while true;do
        case "$1" in
            --git_url)
                DOWNLOAD_METHOD="git"
                SOURCE_PATH="$2" 
                shift 2;;
            --git_branch)
                GIT_BRANCH="$2" 
                shift 2;;
            --archive_url)
                DOWNLOAD_METHOD="http"
                SOURCE_PATH="$2" 
                shift 2;;
            --local_path)
                DOWNLOAD_METHOD="local"
                SOURCE_PATH="$2" 
                shift 2;;
            --use_ccache)
                USE_CCACHE="$2" 
                shift 2;;
            --clean_env)
                CLEAN_ENV="$2" 
                shift 2;;
            --destination_path)
                DESTINATION_PATH="$2" 
                shift 2;;
            --build_path)
                BASE_DIR="$2"
                shift 2;;
            --mount_destination)
                MOUNT_DESTINATION="$2" 
                shift 2;;
            --thread_number)
                THREAD_NUMBER="$2" 
                shift 2;;
            --debian_os_version)
                DEBIAN_OS_VERSION="$2" 
                shift 2;;
            --install_deps)
                INSTALL_DEPS="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ ! "$DOWNLOAD_METHOD" ]];then
        printf "No download method was specified.Exiting."
        exit 1
    fi
    if [[ ! "$DESTINATION_PATH" ]];then
        printf "You need to specify a destination path."
        exit 1
    else
        if [[ ! -e "$DESTINATION_PATH" ]];then
            mkdir -p "$DESTINATION_PATH"
            DESTINATION_PATH=`readlink -e "$DESTINATION_PATH"`
        fi
    fi

    if [[ "$CLEAN_ENV" == "True" ]];then
        clean_env_"$os_FAMILY" "$BASE_DIR" "$os_PACKAGE"
    fi

    if [[ ! -e "$BASE_DIR" ]];then
        mkdir -p "$BASE_DIR"
    fi

    if [[ "$USE_CCACHE" == "True" ]];then
        PATH=/usr/lib/ccache:$PATH
    fi
    if [[ "$INSTALL_DEPS" == "True" ]];then
        install_deps_"$os_FAMILY"
    fi
    build_kernel "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DOWNLOAD_METHOD" "$DESTINATION_PATH" \
        "$THREAD_NUMBER" "$GIT_BRANCH"
    build_daemons "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DOWNLOAD_METHOD" "$DEBIAN_OS_VERSION" \
        "$DESTINATION_PATH" "$DEP_PATH"
}

main $@
