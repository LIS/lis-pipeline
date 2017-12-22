#!/bin/bash

set -xe

add_root_ssh_ubuntu() {
    vm_username="$1"
    
    sudo cp -rf /home/"$vm_username"/.ssh/authorized_keys /
    sudo sed -i 's%#AuthorizedKeysFile.*%AuthorizedKeysFile /authorized_keys%' /etc/ssh/sshd_config
}

add_root_ssh_centos() {
    vm_username="$1"
    
    sudo ssh-keygen
    sudo cat /home/"$vm_username"/.ssh/authorized_keys > /root/.ssh/authorized_keys
    sudo sed -i 's%#PermitRootLogin Yes%PermitRootLogin Yes%' /etc/ssh/sshd_config
}

prepare_lisa_ubuntu() {
    sudo apt update
    sudo apt -y install binutils at dos2unix
    sudo systemctl enable atd.service
}

prepare_lisa_centos() {
    sudo yum -y install binutils at dos2unix
    sudo systemctl enable atd.service
}

prepare_vm_ubuntu() {
    artifacts_path="$1"
    root_key="$2"
    lisa="$3"
    target_artifacts="$4"
    vm_username="$5"
    
    pushd "$artifacts_path"
    if [[ "$target_artifacts" == "all" ]];then
        sudo dpkg -i *.deb
    elif [[ "$target_artifacts" == "azure" ]];then
        sudo DEBIAN_FRONTEND=noninteractive apt purge linux-cloud-tools-common
        sudo DEBIAN_FRONTEND=noninteractive dpkg -i $(ls -I *dbg* | grep linux-image)
        sudo DEBIAN_FRONTEND=noninteractive dpkg -i hyperv-daemons*
    fi
    popd
    
    if [[ "$root_key" == "true" ]];then
        add_root_ssh_ubuntu "$vm_username"
    fi
    if [[ "$lisa" == "true" ]];then
        prepare_lisa_ubuntu
    fi
}

prepare_vm_centos() {
    artifacts_path="$1"
    root_key="$5"
    lisa="$6"
    target_artifacts="$4"
    vm_username="$5"
    
    pushd "$artifacts_path"
    if [[ "$target_artifacts" == "all" ]];then
        sudo rpm -ivh *.rpm 
    elif [[ "$target_artifacts" == "kernel" ]];then
        sudo rpm -ivh kernel* --force --nodeps
    fi
    popd
    sudo sed -i 's%GRUB_DEFAULT=.*%GRUB_DEFAULT=0%' /etc/default/grub
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    
    if [[ "$root_key" == "true" ]];then
        add_root_ssh_centos "$vm_username"
    fi
    if [[ "$lisa" == "true" ]];then
        prepare_lisa_centos
    fi    
    
}

main() {
    OS_TYPE=""
    ARTIFACTS_PATH=""
    ROOT_KEY="false"
    PREPARE_LISA="false"
    TARGET_ARTIFACTS="kernel"
    VM_USERNAME=""

    while true;do
        case "$1" in
            --os_type)
                OS_TYPE="$2"
                shift 2;;
            --artifacts_path)
                ARTIFACTS_PATH="$2"
                shift 2;;
            --root_key)
                ROOT_KEY="$2"
                shift 2;;
            --prepare_lisa)
                PREPARE_LISA="$2"
                ROOT_KEY="true"
                shift 2;;
            --target_artifacts)
                TARGET_ARTIFACTS="$2"
                shift 2;;
            -vm_username)
                VM_USERNAME="$2"
                shift 2;;
            *) break ;;
        esac
    done
    
    if [[ "$OS_TYPE" == "ubuntu" ]];then
        ARTIFACTS_PATH="${ARTIFACTS_PATH}/deb"
    elif [[ "$OS_TYPE" == "centos" ]];then
        ARTIFACTS_PATH="${ARTIFACTS_PATH}/rpm"
    fi
 
    if [[ ! -d "$ARTIFACTS_PATH" ]];then
        echo "Cannot find artifacts folder"
        exit 1;
    fi
    
    prepare_vm_${OS_TYPE} "$ARTIFACTS_PATH" "$ROOT_KEY" "$LISA" "$TARGET_ARTIFACTS" "$VM_USERNAME"
}

main $@