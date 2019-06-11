pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

function get_lis_os {
    os_type="$1"
    os_version="$2"
    
    os_type="$(echo "$os_type" | tr /a-z/ /A-Z/)"
    os_version=${os_version//.}
    echo "${os_type}${os_version}"
}

function prepare_vm {
    os_version="$1"
    kernel_repo="$2"
    kernel_version="$3"
    rhel_username="$4"
    rhel_password="$5"

    subscription-manager register --force --username "${rhel_username}" --password "${rhel_password}"
    subscription-manager attach --auto
    subscription-manager release --set=${os_version}
    IFS='^'
    read -ra kernel_repos <<< "$kernel_repo"
    for repo in "${kernel_repos[@]}"; do
        subscription-manager repos --enable=${repo}
    done
    yum clean all
    yum -y install wget gcc redhat-lsb-core
    yum -y install kernel-${kernel_version}
    if [[ $? -ne 0 ]];then
	    printf "\n kernel-${kernel_version} installation failed \n"
    fi
    yum -y install kernel-devel-${kernel_version}
}

function install_modules {
    modules_path="$1"
    kernel_version="$2"

    #Check whether ERRATA kernel is installed or not
    installed_kernel_version=$(uname -r)
    required_kernel_version=$kernel_version.$(uname -m)

    if [[ $installed_kernel_version != $required_kernel_version ]];then
            printf "\nERRATA kernel $kernel_version not installed \n"
            printf "\nAborting LIS installation \n"
            return 0
    fi

    pushd "${modules_path}"
    update_folder="$(ls -1v | grep update | tail -1)"
    pushd "./${update_folder}"
    
    printf "\nInstalling: "
    if [[ ${update_folder} != "" ]];then
        printf "${update_folder} \n\n"
    else
        printf "base version \n\n"
    fi
    printf "\nKMOD Install: \n"
    printf "\nKMOD Install: \n" 1>&2
    rpm -ivh "$(ls kmod* | grep -vE 'i686')"
    if [[ $? -ne 0 ]];then
	    printf "\n$(ls kmod* | grep -vE 'i686') installation failed \n"
    fi
    printf "\nLIS Install: \n"
    printf "\nLIS Install: \n" 1>&2
    rpm -ivh "$(ls microsoft* | grep -vE 'src|debug|i686')"
    if [[ $? -ne 0 ]];then
	    #Not critical for aborting. Print message for information.
	    printf "\n$(ls microsoft* | grep -vE 'src|debug|i686') installation failed \n"
    fi
    
    popd
    popd
}

function main {
    SECTION="$sec"
    OS_VERSION="$os_ver"
    KERNEL_REPO="$kernel_repolist"
    WORK_DIR="$workdir"
    KERNEL_VERSION="$kernel_ver"
    RHEL_USERNAME="$rhel_user"
    RHEL_PASSWORD="$rhel_pass"
    LIS_PATH="$lis_path"

    mkdir -p "$WORK_DIR"
    pushd "$WORK_DIR"
    rm -f "./*.log"
    
    if [[ "$SECTION" == "install_kernel" ]];then        
        MAJOR_VERSION="${OS_VERSION%.*}"
        prepare_vm "$OS_VERSION" "$KERNEL_REPO" "$KERNEL_VERSION" "$RHEL_USERNAME" "$RHEL_PASSWORD"
    elif [[ "$SECTION" == "install_lis" ]];then
        MODULES_DIR="$(get_lis_os RPMS "${OS_VERSION}")"
        install_modules "${LIS_PATH}/${MODULES_DIR}" "$KERNEL_VERSION"
    fi
    popd
}

main $@
