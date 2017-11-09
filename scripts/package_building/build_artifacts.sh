#!/bin/bash

set -xe

. utils.sh

function install_deps_rhel {
    #
    # Installing packages required for the build process.
    #
    rpm_packages=(rpm-build rpmdevtools yum-utils ncurses-devel hmaccalc zlib-devel \ 
    binutils-devel elfutils-libelf-devel openssl-devel wget git ccache bc fakeroot crudini \
    asciidoc audit-devel binutils-devel xmlto bison flex gtk2-devel libdw-devel libelf-devel \
    xz-devel libnuma-devel newt-devel openssl-devel xmlto zlib-devel)
    sudo yum groups mark install "Development Tools"
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install ${rpm_packages[@]}
    
    if [[ "$USE_CCACHE" == "True" ]];then
        PATH="/usr/lib64/ccache:"$PATH
    fi
}

function install_deps_debian {
    #
    # Installing packages required for the build process.
    #
    deb_packages=(libncurses5-dev xz-utils libssl-dev bc ccache kernel-package \
    devscripts build-essential lintian debhelper git wget bc fakeroot crudini flex bison asciidoc)
    DEBIAN_FRONTEND=noninteractive sudo apt-get -y install ${deb_packages[@]}
    
    if [[ "$USE_CCACHE" == "True" ]];then
        PATH="/usr/lib/ccache:"$PATH
    fi
}

function prepare_env_debian (){
    #
    # Prepare environment for build process (Debian, Ubuntu)
    #
    base_dir="$1"
    build_state="$2"
    
    pushd "$base_dir"
    
    if [[ "$build_state" != "kernel" ]] && [[ -d "$build_state" ]];then
        rm -rf ./${build_state}
    fi
    if [[ $build_state == "daemons" ]];then
        mkdir -p ./${build_state}/hyperv-daemons/debian
    elif [[ $build_state == "tools" ]];then
        mkdir -p ./${build_state}/hyperv-tools/debian
    elif [[ $build_state == "kernel" ]];then 
        mkdir -p ./${build_state}
    elif [[ $build_state == "perf" ]];then
        mkdir ./${build_state}
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
    if [[ "$build_state" != "kernel" ]] && [[ -d "$build_state" ]];then
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
    git_branch="$3"
    
    pushd "${base_dir}/kernel"
    wget $source_path
    tarBall="$(ls *tar*)"
    tar xf $tarBall
    popd
    source="${base_dir}/kernel/${tarBall%.tar*}"
    echo "$source"
    pushd "$source"
    if [[ -d ".git" ]];then
        git checkout $git_branch||true
    fi
    popd   
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
    pushd "$source"
    git reset --hard > /dev/null
    git fetch > /dev/null
    git checkout "$git_branch" > /dev/null
    git pull > /dev/null
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
    git_branch="$3"
    
    pushd "${base_dir}/kernel"
    cp -rf "$source_path" .
    source="${base_dir}/kernel/$(ls)"
    echo "$source"
    popd
    pushd "$source"
    if [[ -d ".git" ]];then
        git checkout $git_branch||true
    fi
    popd
}

function prepare_kernel_debian (){
    #
    # Make kernel config file 
    #
    source="$1"
    
    pushd "$source"  
    if [[ -e "$KERNEL_CONFIG" ]];then
        cp "$KERNEL_CONFIG" .config
    else
        make olddefconfig
    fi
    touch REPORTING-BUGS
    popd
}

function prepare_kernel_rhel (){
    #
    # Make kernel cofig file
    #
    source="$1"
    
    pushd "${source}"
    if [[ -e "tools/hv/lis-daemon.spec" ]];then
        mv "tools/hv/lis-daemon.spec" "tools/hv/lis-daemon.oldspec"
    fi
    if [[ -e "$KERNEL_CONFIG" ]];then
        cp "$KERNEL_CONFIG" .config
    else
        make olddefconfig
    fi
    popd
}

function prepare_daemons_debian (){
    #
    # Copy daemons sources and dependency files for deb packet build process
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    debian_version="$4"
    
    pushd "$source"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    # Copy daemons sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp ./tools/hv/* "${base_dir}/daemons/hyperv-daemons"
        sed -i "s#\.\./\.\.#'$source'#g" "${base_dir}/daemons/hyperv-daemons/Makefile"
    fi
    popd
    pushd "${base_dir}/daemons/hyperv-daemons"
    dch --create --distribution unstable --package "hyperv-daemons" \
        --newversion "$kernel_version" "jenkins"
    for i in *.sh;do
        mv "$i" "${i%.*}"
    done
    if [ "$debian_version" -ge 15 ];then
        cp "${dep_path}/16/"* "./debian"
    else
        cp "${dep_path}/14/"* "./debian"
    fi
    sed -i -e "s/Standards-Version:.*/Standards-Version: $kernel_version/g" "./debian/control"
    popd
}

function prepare_daemons_rhel (){
    #
    # Copy daemons sources and dependency files for rpm packet build process
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    
    pushd "${base_dir}/daemons"
    yumdownloader --source hyperv-daemons
    rpm -ivh *.rpm
    rm -f *.rpm
    popd
    pushd "$source"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    release="${kernel_version##*-}"
    if [[ "$release" != "$kernel_version" ]];then
        kernel_version="${kernel_version%-*}"
        kernel_version="${kernel_version#*-}"
    else
        release=""
    fi
    # Copy daemons sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp -f ./tools/hv/* "${base_dir}/daemons/rpmbuild/SOURCES"
        sed -i "s#\.\./\.\.#'$source'#g" "${base_dir}/daemons/rpmbuild/SOURCES/Makefile"
    fi
    popd
    pushd "${base_dir}/daemons/rpmbuild"
    if [[ -e "${dep_path}/lis-daemon.spec" ]];then
        cp "${dep_path}/lis-daemon.spec" "./SPECS"
        sed -i -e "s/Version:.*/Version:  $kernel_version/g" "SPECS/lis-daemon.spec"
        if [[ "$release" != "" ]];then
            sed -i -e "s/Release:.*/Release:  $release/g" "SPECS/lis-daemon.spec"
        fi  
        spec="lis-daemon.spec"
    else
        sed -i -e "s/Version:.*/Version:  $kernel_version/g" "SPECS/hyperv-daemons.spec"
        if [[ "$release" != "" ]];then
            sed -i -e "s/Release:.*/Release:  $release/g" "SPECS/hyperv-daemons.spec"
        fi
        sed -i '/Patch/d' "SPECS/hyperv-daemons.spec"
        sed -i '/%patch/d' "SPECS/hyperv-daemons.spec"
        sed -i '/Requires:/d' "SPECS/hyperv-daemons.spec"
        spec="hyperv-daemons.spec"
    fi
    popd
}

function prepare_tools_debian (){
    #
    # Copy tools sources and dependency files
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    debian_version="$4"
    
    pushd "$source"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    # Copy sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp ./tools/hv/lsvmbus "${base_dir}/tools/hyperv-tools"
    fi
    popd
    pushd "${base_dir}/tools/hyperv-tools"
    dch --create --distribution unstable --package "hyperv-tools" \
        --newversion "$kernel_version" "tools"
    cp "${dep_path}/tools/"* "./debian"
    popd
}

function prepare_tools_rhel (){
    #
    # Copy tools sources and dependency files
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    
    mkdir -p "${base_dir}/tools/rpmbuild/"{RPMS,SRPMS,BUILD,SOURCES,SPECS,tmp}
    pushd "$source"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    # Copy daemons sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp -f ./tools/hv/lsvmbus "${base_dir}/tools/rpmbuild/SOURCES"
    fi
    popd
    pushd "${base_dir}/tools/rpmbuild"
    if [[ -e "${dep_path}/tools/lis-tools.spec" ]];then
        cp "${dep_path}/tools/lis-tools.spec" "./SPECS"
        spec="lis-tools.spec"
    else
        exit 1
    fi
    popd
}

function prepare_perf_rhel (){
    #
    # Copy tools sources and dependency files
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    
    mkdir -p "${base_dir}/perf/rpmbuild/"{RPMS,SRPMS,BUILD,SOURCES,SPECS,tmp}
    pushd "$source"
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    release="${kernel_version##*-}"
    if [[ "$release" != "$kernel_version" ]];then
        kernel_version="${kernel_version%-*}"
        kernel_version="${kernel_version#*-}"
    else
        release=""
    fi
    if [[ ! -d "tools/perf" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        cp -fr ./tools "${base_dir}/perf/rpmbuild/SOURCES"
    fi
    popd
    pushd "${base_dir}/perf/rpmbuild"
    if [[ -e "${dep_path}/perf/lis-perf.spec" ]];then
        cp "${dep_path}/perf/lis-perf.spec" "./SPECS"
        sed -i -e "s/Version:.*/Version:  $kernel_version/g" "SPECS/lis-perf.spec"
        if [[ "$release" != "" ]];then
            sed -i -e "s/Release:.*/Release:  $release/g" "SPECS/lis-perf.spec"
        fi
        spec="lis-perf.spec"
    else
        exit 1
    fi
    popd
}

function prepare_perf_debian (){
    #
    # Copy tools sources and dependency files
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    
    pushd "$source"
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    pack_folder="${base_dir}/perf/linux-perf_${kernel_version}"    
    if [[ -d "$pack_folder" ]];then
        rm -rf "$pack_folder"
    fi
    mkdir "$pack_folder"
    if [[ ! -d "tools/perf" ]];then
        printf "Linux source folder expected"
        exit 3
    else 
        pushd "${source}/tools/perf"
        make DESTDIR="$pack_folder" install install-doc
        pushd "$pack_folder"
        mkdir "./usr"
        mv ./bin ./lib64 ./libexec ./share ./usr
        popd
        popd
    fi
    popd
    mkdir "${pack_folder}/DEBIAN"
    cp "${dep_path}/perf/"* "${pack_folder}/DEBIAN/"
    sed -i -e "s/Version:.*/Version:  $kernel_version/g" "${pack_folder}/DEBIAN/control"
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

    artifacts_dir="${base_dir}/${build_state}/"
    if [[ -d "$artifacts_dir" ]];then
        rm -f $artifacts_dir/*.deb
    else
        exit 1
    fi
    if [[ "$build_state" == "kernel" ]];then
        pushd "$source"
        fakeroot make-kpkg --initrd -j"$thread_number" kernel_image kernel_headers kernel_source kernel_debug
        popd
    elif [[ "$build_state" == "daemons" ]];then
        pushd "${base_dir}/daemons/hyperv-daemons"
        echo "y" | debuild -us -uc
        popd
    elif [[ "$build_state" == "tools" ]];then
        pushd "${base_dir}/tools/hyperv-tools"
        debuild -us -uc
        popd
    elif [[ "$build_state" == "perf" ]];then
        pushd "${base_dir}/perf/"
        dpkg-deb --build linux-perf_${kernel_version}
        popd
    fi
    copy_artifacts "$artifacts_dir" "$destination_path"
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

    if [[ "$build_state" == "kernel" ]];then
        artifacts_dir="${base_dir}/${build_state}/rpmbuild/RPMS/x86_64/"
    elif [[ "$build_state" == "daemons" ]];then
        artifacts_dir="${base_dir}/${build_state}/rpmbuild/RPMS/x86_64/"
    elif [[ "$build_state" == "perf" ]];then
        artifacts_dir="${base_dir}/${build_state}/rpmbuild/RPMS/x86_64/"
    else
        artifacts_dir="${base_dir}/${build_state}/rpmbuild/RPMS/noarch/"
    fi
    source_package_dir="${base_dir}/${build_state}/rpmbuild/SRPMS/"
    
    if [[ -d "$artifacts_dir" ]];then
        rm -f $artifacts_dir/*
    fi
    
    if [[ "$build_state" == "kernel" ]];then
        if [[ -d "$source_package_dir" ]];then
            rm -f $source_package_dir/*
        fi
        pushd "$source"
        make rpm -j"$thread_number"
        popd
        copy_artifacts "$source_package_dir" "$destination_path"
    elif [[ "$build_state" == "daemons" ]];then
        pushd "${base_dir}/daemons/rpmbuild"
        rpmbuild -ba "SPECS/$spec"
        popd
    elif [[ "$build_state" == "tools" ]];then
        pushd "${base_dir}/tools/rpmbuild"
        rpmbuild -ba "SPECS/$spec"
        popd
    elif [[ "$build_state" == "perf" ]];then
        pushd "${base_dir}/perf/rpmbuild"
        rpmbuild -ba "SPECS/$spec"
        popd
    fi
    copy_artifacts "$artifacts_dir" "$destination_path"
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
    source_package="$8"

    prepare_env_"${os_family}" "$base_dir" "$build_state"
    source="$(get_sources_${download_method} $base_dir $source_path $git_branch)"
    prepare_kernel_"${os_family}" "$source"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$destination_path" "$source_package"
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
    prepare_daemons_"${os_family}" "$base_dir" "$source" "$dep_path" "$debian_version"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$destination_path" "$spec"
}

function build_tools (){
    #
    # Build the tools
    #
    base_dir="$1"
    source_path="$2"
    os_family="$3"
    destination_path="$4"
    dep_path="$5"
    build_state="tools"
    
    prepare_env_"${os_family}" "$base_dir" "$build_state"
    prepare_tools_"${os_family}" "$base_dir" "$source" "$dep_path"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$destination_path" "$spec"
}

function build_perf (){
    #
    # Build perf package
    #
    base_dir="$1"
    source_path="$2"
    os_family="$3"
    destination_path="$4"
    dep_path="$5"
    build_state="perf"
    
    prepare_env_"${os_family}" "$base_dir" "$build_state"
    prepare_perf_"${os_family}" "$base_dir" "$source" "$dep_path"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$destination_path" "$spec"
}
    
function get_job_number (){
    #
    # Multiply current number of threads with a number
    # Usage:
    #   ./build_artifacts.sh --thread_number x10
    #
    multi="$1"
    cores="$(cat /proc/cpuinfo | grep -c processor)"
    result="$(expr $cores*$multi | bc)"
    echo ${result%.*}
}

function clean_env_debian (){
    #
    # Removing sources and files required by the build process.
    #
    base_dir="$1"
    
    if [[ -d "$BASE_DIR" ]];then
        rm -rf "${BASE_DIR}/"*
    fi
}

function clean_env_rhel (){
    #
    # Removing sources and files required by the build process.
    #
    base_dir="$1"
    
    if [[ -d "$BASE_DIR" ]];then
        rm -rf "${BASE_DIR}/"*
    fi
    
    if [[ -a "$HOME/.rpmmacros" ]];then
        rm -f "$HOME/.rpmmacros"
    fi
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
    INI_FILE="$(pwd)/kernel_versions.ini"
    USE_CCACHE="False"
    GIT_BRANCH="master"
    CLEAN_ENV="False"
    DOWNLOAD_METHOD=""
    THREAD_NUMBER="2"
    INSTALL_DEPS="True"
    DEBIAN_OS_VERSION="${os_RELEASE%.*}"
    KERNEL_CONFIG="./Microsoft/config-azure"
    DEFAULT_BRANCH="stable"
    
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
            --kernel_config)
                KERNEL_CONFIG="$2"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ "$INSTALL_DEPS" == "True" ]];then
        install_deps_"$os_FAMILY"
    fi
    
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
    
    if [[ "${THREAD_NUMBER:0:1}" == "x" ]];then
        THREAD_NUMBER="$(get_job_number ${THREAD_NUMBER#x*})"
    fi

    INITIAL_BRANCH_NAME=$GIT_BRANCH
    if [[ "$GIT_BRANCH" == "" ]];then
        GIT_BRANCH="$DEFAULT_BRANCH"
    fi
    GIT_BRANCH="$(get_branch_from_ini "$GIT_BRANCH" "$INI_FILE")"

    BASE_DESTINATION_PATH=$DESTINATION_PATH
    DESTINATION_PATH="$BASE_DESTINATION_PATH/$GIT_BRANCH-$(date +'%d%m%Y')"
    DESTINATION_PATH="$(check_destination_dir $DESTINATION_PATH $os_PACKAGE)"
    
    if [[ "$CLEAN_ENV" == "True" ]];then
        clean_env_"$os_FAMILY" "$BASE_DIR" "$os_PACKAGE"
    fi

    if [[ ! -e "$BASE_DIR" ]];then
        mkdir -p "$BASE_DIR"
    fi

    build_kernel "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DOWNLOAD_METHOD" "$DESTINATION_PATH" \
        "$THREAD_NUMBER" "$GIT_BRANCH"
    build_daemons "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DOWNLOAD_METHOD" "$DEBIAN_OS_VERSION" \
        "$DESTINATION_PATH" "$DEP_PATH"
    build_tools "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DESTINATION_PATH" "$DEP_PATH"
    build_perf "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DESTINATION_PATH" "$DEP_PATH"

    if [[ "$INITIAL_BRANCH_NAME" == "stable" ]] || [[ "$INITIAL_BRANCH_NAME" == "unstable" ]];then
        pushd $BASE_DESTINATION_PATH
        link_path="./latest"
        sudo ln -snf "./$GIT_BRANCH-$(date +'%d%m%Y')" $link_path
        popd
    fi
}

main $@
