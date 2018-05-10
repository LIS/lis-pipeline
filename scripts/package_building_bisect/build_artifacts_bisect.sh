#!/bin/bash

set -xe -o pipefail

. ../package_building/utils.sh
. utils.sh

function clean_env_debian () {
    #
    # Removing sources and files required by the build process.
    #
    local base_dir="$1"
    
    if [[ -d "$base_dir" ]];then
        pushd $base_dir
        find . -name "*.deb" | xargs rm -f
        git_folders=$(find . -name .git -type d -prune)
        IFS=$'\n'
        for folder in $git_folders; do
            dir=${folder%.*}
            pushd "$dir"
                make clean
                git clean -x -f
            popd
        done
        IFS=$' '
        popd
    fi
}

function clean_env_rhel () {
    #
    # Removing sources and files required by the build process.
    #
    local base_dir="$1"
    
    if [[ -d "${base_dir}/perf" ]];then
        sudo chown -R $(whoami) "${base_dir}/perf"
        sudo chown $(whoami) "${base_dir}"
    fi
    if [[ -d "$base_dir" ]];then
        pushd $base_dir
        find . -name "*.rpm" | xargs rm -f
        git_folders=$(find . -name .git -type d -prune)
        IFS=$'\n'
        for folder in $git_folders; do
            dir=${folder%.*}
            pushd "$dir"
                make clean
                git clean -x -f
            popd
        done
        IFS=$' '
        popd
    fi
      
    if [[ -a "$HOME/.rpmmacros" ]];then
        rm -f "$HOME/.rpmmacros"
    fi
}

function prepare_ccache () {
    local ccache_dir="$1"; shift

    export CCACHE_DIR="$ccache_dir"
    export CC="ccache gcc"
    export PATH="/usr/lib/ccache:$PATH"
}

function get_source () {
    local base_dir="$1"; shift
    local source_path="$1"; shift

    git_folder_git_extension=${source_path##*/}
    git_folder=${git_folder_git_extension%%.*}
    repository="${base_dir}/kernel/${git_folder}"

    echo "$repository"
}

function get_sources_git () {
    #
    # Downloading kernel sources from git
    #
    local base_dir="$1"; shift
    local source_path="$1"; shift
    local git_branch="$1"; shift
    local git_commit_id="$1"; shift
    local repository="$1"

    git_folder=${repository##*/}
    mkdir -p "$base_dir/kernel"

    pushd "${base_dir}/kernel"
    if [[ ! -d "$repository" ]];then
        git clone $git_params "$source_path"
        pushd "$git_folder"
            git config --global gc.auto 0
        popd
    else
        pushd "$git_folder"
        git remote set-url origin "$source_path"
        popd
    fi
    pushd "$git_folder"
    git fetch --all
    git reset --hard origin/master
    git checkout -f "$git_branch" && git checkout -f "$git_commit_id"
    if [[ $? -ne 0 ]];then
        exit 1
    fi
    popd
    popd
}

function prepare_kernel_debian () {
    #
    # Make kernel config file 
    #
    shift
    local repository="$1"; shift 2
    local dep_path="$1"; shift
    
    pushd "$repository"
    kernel_version="$(make kernelversion)"
    if [[ "$KERNEL_CONFIG" != ".config" ]];then
        if [[ -e "./$KERNEL_CONFIG" ]];then
            cp "$KERNEL_CONFIG" .config
        elif [[ -e "${dep_path%/*}/kernel_config/$KERNEL_CONFIG" ]];then
            cp "${dep_path%/*}/kernel_config/$KERNEL_CONFIG" .config
        fi
    fi
    make olddefconfig
    cp "$dep_path/setlocalversion" ./scripts
    git_tag=$(get_git_tag $repository HEAD 12)
    sed -i -e "s/%version%/-${git_tag}/g" ./scripts/setlocalversion
    touch REPORTING-BUGS
    popd
}

function prepare_kernel_rhel () {
    #
    # Make kernel cofig file
    #
    local base_dir="$1"; shift
    local repository="$1"; shift
    local package_prefix="$1"; shift
    local dep_path="$1"
    
    cat << EOF > "$HOME/.rpmmacros"
%packager test
%_topdir ${base_dir}/kernel/rpmbuild
%_tmppath ${base_dir}/kernel/rpmbuild/tmp
EOF

    pushd "$repository"
    if [[ -e "tools/hv/lis-daemon.spec" ]];then
        mv "tools/hv/lis-daemon.spec" "tools/hv/lis-daemon.oldspec"
    fi
    if [[ "$KERNEL_CONFIG" != ".config" ]];then
        if [[ -e "./$KERNEL_CONFIG" ]];then
            cp "$KERNEL_CONFIG" .config
        elif [[ -e "${dep_path%/*}/kernel_config/$KERNEL_CONFIG" ]];then
            cp "${dep_path%/*}/kernel_config/$KERNEL_CONFIG" .config 
        fi
    fi
    # Select the default config option for any new options in the newer kernel version
    make olddefconfig
    kernel_tag=$(git log -1 --pretty=format:"%h")
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
    local base_dir="$1"; shift
    local repository="$1"; shift
    local dep_path="$1"; shift
    local debian_version="$1"; shift
    local package_prefix="$1"

    build_folder="hyperv-daemons"
    if [[ "$package_prefix" != "" ]];then
        build_folder="${package_prefix}-${build_folder}"
    fi
    pushd "$repository"
    kernel_version="$(make kernelversion)"
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

function build_daemons_debian () {
    local base_dir="$1"; shift
    local repository="$1"; shift
    local dep_path="$1"; shift
    local debian_version="$1"; shift
    local package_prefix="$1"

    local build_state="daemons"

    pushd "$base_dir"
    if [[ -d "$build_state" ]];then
        rm -rf "./$build_state"
    fi
    mkdir -p "./$build_state/hyperv-daemons/debian"
    popd

    prepare_daemons_debian "$base_dir" "$repository" "$dep_path" "$debian_version" \
                           "$package_prefix"

    artifacts_dir="${base_dir}/${build_state}/"
    if [[ -d "$artifacts_dir" ]];then
        rm -f $artifacts_dir/*.deb
    else
        exit 1
    fi
    if [[ "$build_state" == "daemons" ]];then
        build_dir="hyperv-daemons"
        if [[ "$PACKAGE_PREFIX" != "" ]];then
            build_dir="${PACKAGE_PREFIX}-${build_dir}"
        fi
        pushd "${base_dir}/daemons/${build_dir}"
        echo "y" | debuild -us -uc
        popd
    fi
    copy_artifacts "$artifacts_dir" "$destination_path"
}

function build_debian () {
    #
    # Building the kernel or daemons for deb based OSs
    #
    local base_dir="$1"; shift
    local repository="$1"; shift
    local build_state="$1"; shift
    local thread_number="$1"; shift
    local destination_path="$1"; shift
    local build_date="$1"

    artifacts_dir="${base_dir}/kernel/"

    pushd "$repository"
    params="--rootcmd fakeroot --initrd  --revision $build_date -j$thread_number"
    if [[ "$package_prefix" != "" ]];then
        params="--stem $PACKAGE_PREFIX $params"
    fi
    make-kpkg $params kernel_image
    popd
    copy_artifacts "$artifacts_dir" "$destination_path"
}

function build_rhel {
    #
    # Building the kernel or daemons for rpm based OSs
    #
    local base_dir="$1"; shift
    local repository="$1"; shift
    local build_state="$1"; shift
    local thread_number="$1"; shift
    local destination_path="$1"

    artifacts_dir="${base_dir}/kernel/rpmbuild/RPMS/x86_64/"
    source_package_dir="${base_dir}/kernel/rpmbuild/SRPMS/"

    if [[ -d "$artifacts_dir" ]]; then
        rm -f $artifacts_dir/*
    fi

    if [[ -d "$source_package_dir" ]]; then
        rm -f $source_package_dir/*
    fi

    pushd "$repository"
    make rpm -j"$thread_number"
    sed -i -e "s/echo \"Name:.*/echo \"Name: kernel\"/g" "./scripts/package/mkspec"
    popd
    copy_artifacts "$artifacts_dir" "$destination_path"
    copy_artifacts "$source_package_dir" "$destination_path"
}

function set_ini () {
    local kernel_version_file="$1"; shift
    local repository="$1"; shift
    local destination_path="$1"; shift
    local folder_prefix="$1"; shift
    local os_package="$1"

    pushd $repository
    kernel_version=$(make kernelversion)
    kernel_tag=$(git log -1 --pretty=format:"%h")
    popd

    destination_folder_tmp=$(dirname "$destination_path")
    destination_folder=$(basename "$destination_folder_tmp")

    crudini --set $kernel_version_file KERNEL_BUILT version $kernel_version
    crudini --set $kernel_version_file KERNEL_BUILT git_tag $kernel_tag
    crudini --set $kernel_version_file KERNEL_BUILT folder  $destination_folder
}

function main () {
    os_info="$(get_os_version)"
    #Ex : os_info="os_VENDOR=Ubuntu os_RELEASE=16.04 os_UPDATE=4 os_PACKAGE=deb os_PACKAGE_MANAGER=apt os_CODENAME=xenial"
    for info in $os_info;do
        var_name="${info%=*}"
        var_value="${info#*=}"
        declare $var_name="$var_value"
    done

    KERNEL_VERSION_FILE='../package_building/kernel_versions.ini'

    BASE_DIR="$(pwd)/temp_build"
    DEP_PATH=$(realpath "../package_building/deps-lis/${os_PACKAGE}")
    INI_FILE="$(pwd)/kernel_versions.ini"
    DEBUG_CONFIG_PATH="$(pwd)/deps-lis/kernel_config/debug_flags.ini"

    # Mandatory:
    SOURCE_PATH=""
    DESTINATION_PATH=""
    DOWNLOAD_METHOD=""

    # Optional:
    GIT_BRANCH='master'
    BASE_DIR="$(pwd)/temp_build"
    DEBIAN_OS_VERSION="${os_RELEASE%.*}"
    FOLDER_PREFIX='msft'
    THREAD_NUMBER='x2'
    KERNEL_CONFIG='Microsoft/config-azure'
    BUILD_DATE="$(date +'%d%m%Y')"
    GIT_TAG=""

    # Flags:
    INSTALL_DEPS='False'
    USE_KERNEL_PREFIX='True'

    TEMP=$(getopt -o f:g:h:j:n:l:z:x:c:k:m: --long git_url:,git_branch:,git_commit_id:,build_path:,debian_os_version:,artifacts_folder_prefix:,thread_number:,destination_path:,kernel_config:,default_branch:,git_tag:,clone_depth:,patch_file:,create_changelog:,build_date:,custom_build_tag:,use_ccache:,clean_env:,install_deps:,use_kernel_folder_prefix:,enable_kernel_debug: -n 'build_artifacts.sh' -- "$@")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    echo $TEMP

    eval set -- "$TEMP"
    
    while true ; do
        case "$1" in
            --git_url)
                case "$2" in
                    "") shift 2 ;;
                    *) SOURCE_PATH="$2" ; shift 2 ;;
                esac ;;
            --git_branch)
                case "$2" in
                    "") shift 2 ;;
                    *) GIT_BRANCH="$2" ; shift 2 ;;
                esac ;;
            --git_commit_id)
                case "$2" in
                    "") shift 2 ;;
                    *) GIT_COMMIT_ID="$2" ; shift 2 ;;
                esac ;;
            --build_path)
                case "$2" in
                    "") shift 2 ;;
                    *) BASE_DIR="$2" ; shift 2 ;;
                esac;;
            --debian_os_version)
                case "$2" in
                    "") shift 2 ;;
                    *) DEBIAN_OS_VERSION="$2" ; shift 2;;
                esac;;
            --artifacts_folder_prefix)
                case "$2" in
                    "") shift 2 ;;
                    *) FOLDER_PREFIX="$2" ; shift 2 ;;
                esac;;
            --thread_number)
                case "$2" in
                    "") shift 2 ;;
                    *) THREAD_NUMBER="$2" ; shift 2 ;;
                esac;;
            --destination_path)
                case "$2" in
                    "") shift 2 ;;
                    *) DESTINATION_PATH="$2" ; shift 2 ;;
                esac ;;
            --kernel_config)
                case "$2" in
                    "") shift 2 ;;
                    *) KERNEL_CONFIG="$2" ; shift 2 ;;
                esac ;;
            --git_tag)
                case "$2" in
                    "") shift 2 ;;
                    *) GIT_TAG="$2" ; shift 2 ;;
                esac ;;
            --build_date)
                case "$2" in
                    "") shift 2 ;;
                    *) BUILD_DATE="$2" ; shift 2 ;;
                esac ;;
            --install_deps)
                case "$2" in
                    "") shift 2 ;;
                    *) INSTALL_DEPS="$2" ; shift 2 ;;
                esac ;;
            --use_kernel_folder_prefix)
                case "$2" in
                    "") shift 2 ;;
                    *) USE_KERNEL_PREFIX="$2" ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) echo "Wrong parameters!" ; exit 1 ;;
        esac
    done

    local CCACHE_DIR="$BASE_DIR/.ccache"
    
    if [[ "$INSTALL_DEPS" == "True" ]];then
        install_deps_"$os_FAMILY"
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
        THREAD_NUMBER="$(get_job_number ${THREAD_NUMBER#x})"
    fi
    
    if [[ "$USE_KERNEL_PREFIX" == "True" ]];then
        if [[ "$SOURCE_PATH" != "" ]];then
            FOLDER_PREFIX="${SOURCE_PATH##*/}"
            FOLDER_PREFIX="${FOLDER_PREFIX%.*}"
            PACKAGE_PREFIX="$FOLDER_PREFIX"
        else
            exit 1
        fi
    fi

    prepare_ccache "$CCACHE_DIR"
    clean_env_"$os_FAMILY" "$BASE_DIR" "$os_PACKAGE"

    if [[ ! -e "$BASE_DIR" ]];then
        mkdir -p "$BASE_DIR"
    fi

    repository=$(get_source "$BASE_DIR" "$SOURCE_PATH")

    get_sources_git "$BASE_DIR" "$SOURCE_PATH" "$GIT_BRANCH" "$GIT_COMMIT_ID" "$repository"
    destination_path="$(get_destination_path_bisect "$repository" "$DESTINATION_PATH" "$os_PACKAGE" "$BUILD_DATE" "$FOLDER_PREFIX")"
    prepare_kernel_"$os_FAMILY" "$BASE_DIR" "$repository" "$PACKAGE_PREFIX" "$DEP_PATH"

    build_"${os_FAMILY}" "$BASE_DIR" "$repository" "$kernel" "$THREAD_NUMBER" "$destination_path" \
        "$BUILD_DATE"

    if [[ "$os_FAMILY" == "debian" ]]; then
        build_daemons_$os_FAMILY "$BASE_DIR" "$repository" "$DEP_PATH" "$DEBIAN_OS_VERSION" "$PACKAGE_PREFIX"
    fi

    set_ini "$KERNEL_VERSION_FILE" "$repository" "$destination_path" "$FOLDER_PREFIX" "$os_PACKAGE"
}

main $@
