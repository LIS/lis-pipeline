#!/bin/bash

set -xe

. utils.sh

KERNEL_VERSION_FILE='./kernel_versions.ini'

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
    deb_packages=(libncurses5-dev xz-utils libssl-dev libelf-dev bc ccache kernel-package \
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
        sudo rm -rf ./${build_state}
    fi
    mkdir -p ./${build_state}
    popd
}

function build_kernel_metapackages_deb () {
    local source; local kernel_version; local kernel_git_commit; local artifacts_dir;
    source="$1"
    kernel_version="$2"
    kernel_git_commit="$3"
    artifacts_dir="$4"

    pushd "$source"
    commit_message=$(git log -1 --format="%aN <%aE>  %aD" $kernel_git_commit | head -1) 
    popd

    pushd "$artifacts_dir"
    filename=$(find . -name "linux-image*" | head -1)
    kernel_abi=$(basename $filename | gawk '{n=split($$0,v,"-"); print v[4];}')
    popd

    kernel_version="$kernel_version-$kernel_abi"
    kernel_version="$kernel_version-g$kernel_git_commit"
    changelog_loc=$(readlink -f $(find ./kernel_metapackages -name changelog))
    debian_rules_loc=$(readlink -f $(find ./kernel_metapackages -name linux-latest))
    update_changelog "$kernel_version" "$commit_message" "$changelog_loc"
    build_metapackages "$kernel_version" "$destination_path" "$debian_rules_loc"
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
    clone_depth="$4"
    git_folder_git_extension=${source_path##*/}
    git_folder=${git_folder_git_extension%%.*}
    source="${base_dir}/kernel/${git_folder}"
    
    git_params="$source_path"
    if [[ "$clone_depth" != "" ]];then
        git_params="$git_params --depth $clone_depth"
    fi
    pushd "${base_dir}/kernel"
    if [[ ! -d "${source}" ]];then
        git clone "$git_params" > /dev/null
    fi
    pushd "$source"
    git reset --hard > /dev/null
    git fetch > /dev/null
    # Note(avladu): the checkout to master is needed to
    # get from a detached HEAD state
    git checkout -f master > /dev/null
    git checkout -f "$git_branch" > /dev/null
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
    if [[ -e "$KERNEL_CONFIG" ]]&&[[ "$KERNEL_CONFIG" != ".config" ]];then
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
    package_prefix="$2"
    kernel_tag="$3"
    
    pushd "${source}"
    if [[ -e "tools/hv/lis-daemon.spec" ]];then
        mv "tools/hv/lis-daemon.spec" "tools/hv/lis-daemon.oldspec"
    fi
    if [[ -e "$KERNEL_CONFIG" ]]&&[[ "$KERNEL_CONFIG" != ".config" ]];then
        cp "$KERNEL_CONFIG" .config
    else
        make olddefconfig
    fi
    if [[ "$package_prefix" != "" ]];then
        sed -i -e "s/	Name: .*/	Name: ${package_prefix}-kernel/g" "./scripts/package/mkspec"
        sed -i -e "s/\$S	Source: /\$S	Source: ${package_prefix}-/g" "./scripts/package/mkspec"
        sed -i -e "s/\$S\$M	%description -n kernel-devel/\$S\$M	%description -n ${package_prefix}-kernel-devel/g" "./scripts/package/mkspec"
        sed -i -e "s/KERNELPATH := /KERNELPATH := ${package_prefix}-/g" "./scripts/package/Makefile"
        sed -i "s|CONFIG_LOCALVERSION_AUTO=.*|CONFIG_LOCALVERSION_AUTO=n|" ".config"
        sed -i "s|CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"-$kernel_tag\"|" ".config"
        touch .scmversion
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
    package_prefix="$5"
    
    build_folder="hyperv-daemons"
    if [[ "$package_prefix" != "" ]];then
        build_folder="${package_prefix}-${build_folder}"
    fi
    pushd "$source"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    # Copy daemons sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else
        if [[ "$package_prefix" != "" ]];then
            mv "${base_dir}/daemons/hyperv-daemons" "${base_dir}/daemons/$build_folder"
        fi
        cp ./tools/hv/* "${base_dir}/daemons/$build_folder"
        sed -i "s#\.\./\.\.#'$source'#g" "${base_dir}/daemons/$build_folder/Makefile"
    fi
    popd
    pushd "${base_dir}/daemons/$build_folder"
    dch --create --distribution unstable --package "$build_folder" \
        --newversion "$kernel_version" "jenkins"
    for i in *.sh;do
        cp "$i" "${i%.*}"
    done
    if [ "$debian_version" -ge 15 ];then
        cp "${dep_path}/16/"* "./debian"
    else
        cp "${dep_path}/14/"* "./debian"
    fi
    sed -i -e "s/Standards-Version:.*/Standards-Version: $kernel_version/g" "./debian/control"
    sed -i -e "s/Package:.*/Package: $build_folder/g" "./debian/control"
    sed -i -e "s/Source:.*/Source: $build_folder/g" "./debian/control"
    popd
}

function prepare_daemons_rhel (){
    #
    # Copy daemons sources and dependency files for rpm packet build process
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    package_prefix="$5"
    
    pushd "${base_dir}/daemons"
    sudo yumdownloader --source hyperv-daemons
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
    if [[ "$package_prefix" != "" ]];then
        sed -i -e "s/Name:.*/Name:  ${package_prefix}-hyperv-daemons/g" "SPECS/$spec"
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
    package_prefix="$4"
    
    build_folder="hyperv-tools"
    if [[ "$package_prefix" != "" ]];then
        build_folder="${package_prefix}-${build_folder}"
    fi
    pushd "$source"
    # Get kernel version
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    # Copy sources
    if [[ ! -d "tools/hv" ]];then
        printf "Linux source folder expected"
        exit 3
    else
        if [[ "$package_prefix" != "" ]];then
            mv "${base_dir}/tools/hyperv-tools" "${base_dir}/tools/${build_folder}"
        fi
        cp ./tools/hv/lsvmbus "${base_dir}/tools/${build_folder}"
    fi
    popd
    pushd "${base_dir}/tools/${build_folder}"
    dch --create --distribution unstable --package "${build_folder}" \
        --newversion "$kernel_version" "tools"
    cp "${dep_path}/tools/"* "./debian"
    sed -i -e "s/Package:.*/Package: $build_folder/g" "./debian/control"
    sed -i -e "s/Source:.*/Source: $build_folder/g" "./debian/control"
    popd
}

function prepare_tools_rhel (){
    #
    # Copy tools sources and dependency files
    #
    base_dir="$1"
    source="$2"
    dep_path="$3"
    package_prefix="$4"
    
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
    if [[ "$package_prefix" != "" ]];then
        sed -i -e "s/Name:.*/Name:  ${package_prefix}-hyperv-tools/g" "SPECS/$spec"
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
    package_prefix="$4"
    
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
    if [[ "$package_prefix" != "" ]];then
        sed -i -e "s/Name:.*/Name:  ${package_prefix}-perf/g" "SPECS/$spec"
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
    package_prefix="$4"
    
    pushd "$source"
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    if [[ "$package_prefix" == "" ]];then
        pack_folder="${base_dir}/perf/linux-perf_${kernel_version}"
    else
        pack_folder="${base_dir}/perf/${package_prefix}-perf_${kernel_version}"
    fi
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
        dirs=(bin lib64 libexec)
        for dir in ${dirs[@]};do
            for file in $(ls ./$dir);do
                mv "./$dir/$file" "./$dir/${file}_${kernel_version%.*}"
            done
        done
        dir="share/man/man[1-10]"
        for file in $(ls ./$dir);do
            rename "s/$file/perf_${kernel_version%.*}-${file#*perf-}/" ./$dir/$file
        done
        mv ./bin ./lib64 ./libexec ./share ./usr
        popd
        popd
    fi
    popd
    mkdir "${pack_folder}/DEBIAN"
    cp "${dep_path}/perf/"* "${pack_folder}/DEBIAN/"
    sed -i -e "s/Version:.*/Version:  $kernel_version/g" "${pack_folder}/DEBIAN/control"
    if [[ "$package_prefix" != "" ]];then
        sed -i -e "s/Package:.*/Package: ${package_prefix}-perf/g" "${pack_folder}/DEBIAN/control"
        sed -i -e "s/Source:.*/Source: ${package_prefix}-perf/g" "${pack_folder}/DEBIAN/control"
    fi
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
    build_date="$6"
    kernel_version_local="$7"
    kernel_git_commit="$8"

    artifacts_dir="${base_dir}/${build_state}/"
    if [[ -d "$artifacts_dir" ]];then
        rm -f $artifacts_dir/*.deb
    else
        exit 1
    fi
    if [[ "$build_state" == "kernel" ]];then
        pushd "$source"
        params="--rootcmd fakeroot --initrd  --revision $build_date -j$thread_number kernel_image kernel_headers kernel_source kernel_debug"
        if [[ "$PACKAGE_PREFIX" != "" ]];then
            params="--stem $PACKAGE_PREFIX $params"
        fi
        if [[ "$kernel_git_commit" != "" ]];then
            params="--append-to-version -$kernel_git_commit $params"
        fi
        make-kpkg $params
        popd
        build_kernel_metapackages_deb "$source" "$kernel_version_local" "$kernel_git_commit" "$artifacts_dir"
    elif [[ "$build_state" == "daemons" ]];then
        build_dir="hyperv-daemons"
        if [[ "$PACKAGE_PREFIX" != "" ]];then
            build_dir="${PACKAGE_PREFIX}-${build_dir}"
        fi
        pushd "${base_dir}/daemons/${build_dir}"
        echo "y" | debuild -us -uc
        popd
    elif [[ "$build_state" == "tools" ]];then
        build_dir="hyperv-tools"
        if [[ "$PACKAGE_PREFIX" != "" ]];then
            build_dir="${PACKAGE_PREFIX}-${build_dir}"
        fi
        pushd "${base_dir}/tools/${build_dir}"
        debuild -us -uc
        popd
    elif [[ "$build_state" == "perf" ]];then
        pushd "${base_dir}/perf/"
        build_dir="linux-perf_${kernel_version}"
        if [[ "$PACKAGE_PREFIX" != "" ]];then
            build_dir="${PACKAGE_PREFIX}-perf_${kernel_version}"
        fi
        dpkg-deb --build "$build_dir"
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
    build_date="$6"
    kernel_version_local="$7"
    kernel_git_commit="$8"

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
        sed -i -e "s/echo \"Name:.*/echo \"Name: kernel\"/g" "./scripts/package/mkspec"
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
        sudo HOME=$HOME rpmbuild -ba "SPECS/$spec"
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
    base_dest_path="$5"
    thread_number="$6"
    build_state="kernel"
    git_branch="$7"
    build_date="$8"
    folder_prefix="$9"
    package_prefix="${10}"

    prepare_env_"${os_family}" "$base_dir" "$build_state"
    source="$(get_sources_${download_method} $base_dir $source_path $git_branch)"
    pushd $source
    KERNEL_VERSION=$(make kernelversion)
    KERNEL_TAG=$(git log -1 --pretty=format:"%h")
    popd
    GIT_TAG="$(get_git_tag $source HEAD 7)"
    GIT_TAG12="$(get_git_tag $source HEAD 12)"
    DESTINATION_PATH="$(get_destination_path $source $base_dest_path $os_PACKAGE $GIT_TAG $build_date $folder_prefix)"
    prepare_kernel_"${os_family}" "$source" "${package_prefix}" "$GIT_TAG12"
    build_"${os_family}" "$base_dir" "$source" "$build_state" "$thread_number" "$DESTINATION_PATH" \
	  "$build_date" "$KERNEL_VERSION" "$GIT_TAG12" "$package_prefix"
    DESTINATION_FOLDER_TMP=$(dirname "${DESTINATION_PATH}")
    DESTINATION_FOLDER=$(basename "${DESTINATION_FOLDER_TMP}")
    echo "Updating the kernel build information for later usage."
    echo "Changing directory to the kernel sources..."
    crudini --set $KERNEL_VERSION_FILE KERNEL_BUILT version $KERNEL_VERSION
    crudini --set $KERNEL_VERSION_FILE KERNEL_BUILT git_tag $KERNEL_TAG
    crudini --set $KERNEL_VERSION_FILE KERNEL_BUILT folder $DESTINATION_FOLDER
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
    package_prefix="$8"
    build_state="daemons"

    prepare_env_"${os_family}" "$base_dir" "$build_state"
    prepare_daemons_"${os_family}" "$base_dir" "$source" "$dep_path" "$debian_version" "$package_prefix"
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
    package_prefix="$6"
    build_state="tools"
    
    prepare_env_"${os_family}" "$base_dir" "$build_state"
    prepare_tools_"${os_family}" "$base_dir" "$source" "$dep_path" "$package_prefix"
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
    package_prefix="$6"
    build_state="perf"
    
    prepare_env_"${os_family}" "$base_dir" "$build_state"
    prepare_perf_"${os_family}" "$base_dir" "$source" "$dep_path" "$package_prefix"
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
    
    if [[ -d "${base_dir}/perf" ]];then
        sudo chown -R $(whoami) "${base_dir}/perf"
        sudo chown $(whoami) "${base_dir}"
    fi

    if [[ -d "$base_dir" ]];then
        rm -rf "${base_dir}/"*
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
    GIT_TAG=""
    BUILD_DATE="$(date +'%d%m%Y')"
    FOLDER_PREFIX="msft"
    SOURCE_TYPE=""
    
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
            --clone_depth)
                CLONE_DEPTH="$2"
                shift 2;;
            --artifacts_folder_prefix)
                FOLDER_PREFIX="$2"
                shift 2;;
            --build_date)
                # Note(mbivolan): This parameter should be a unix timestamp or a date in the format (ddmmyy)
                if [[ "$2" != "" ]];then
                    BUILD_DATE="$2"
                    shift
                fi
                shift;;
            --use_kernel_folder_prefix)
                USE_KERNEL_PREFIX="$2"
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
    
    if [[ "$USE_KERNEL_PREFIX" == "True" ]];then
        if [[ "$DOWNLOAD_METHOD" == "git" ]] && [[ "$SOURCE_PATH" != "" ]];then
            FOLDER_PREFIX="${SOURCE_PATH##*/}"
            FOLDER_PREFIX="${FOLDER_PREFIX%.*}"
            PACKAGE_PREFIX="$FOLDER_PREFIX"
        else
            exit 1
        fi
    fi
    
    INITIAL_BRANCH_NAME=$GIT_BRANCH
    if [[ "$GIT_BRANCH" == "" ]];then
        GIT_BRANCH="$DEFAULT_BRANCH"
    fi
    GIT_BRANCH="$(get_branch_from_ini "$GIT_BRANCH" "$INI_FILE")"

    BASE_DESTINATION_PATH=$DESTINATION_PATH
    if [[ "$CLEAN_ENV" == "True" ]];then
        clean_env_"$os_FAMILY" "$BASE_DIR" "$os_PACKAGE"
    fi

    if [[ ! -e "$BASE_DIR" ]];then
        mkdir -p "$BASE_DIR"
    fi

    build_kernel "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DOWNLOAD_METHOD" "$BASE_DESTINATION_PATH" \
        "$THREAD_NUMBER" "$GIT_BRANCH" "$BUILD_DATE" "$FOLDER_PREFIX" "$PACKAGE_PREFIX"
    build_daemons "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DOWNLOAD_METHOD" "$DEBIAN_OS_VERSION" \
        "$DESTINATION_PATH" "$DEP_PATH" "$PACKAGE_PREFIX"
    build_tools "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DESTINATION_PATH" "$DEP_PATH" "$PACKAGE_PREFIX"
    build_perf "$BASE_DIR" "$SOURCE_PATH" "$os_FAMILY" "$DESTINATION_PATH" "$DEP_PATH" "$PACKAGE_PREFIX"

    if [[ "$INITIAL_BRANCH_NAME" == "stable" ]] || [[ "$INITIAL_BRANCH_NAME" == "unstable" ]];then
        pushd $BASE_DESTINATION_PATH
        link_path="./latest"
        ln -snf "./$GIT_BRANCH-$BUILD_DATE" $link_path
        popd
    fi
    crudini --set $KERNEL_VERSION_FILE KERNEL_BUILT branch $GIT_BRANCH
    crudini --set $KERNEL_VERSION_FILE KERNEL_BUILT branch_label $INITIAL_BRANCH_NAME
}

main $@
