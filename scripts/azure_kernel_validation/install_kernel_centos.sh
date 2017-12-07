#!/bin/bash
set -xe

install_deps(){
    yum -y install samba cifs-utils openssh-server
}

mount_share(){
    username="$1"
    password="$2"
    samba_path="$3"

    sudo mount -t cifs $samba_path /mnt -o vers=3.0,username=$username,password=$password,dir_mode=0777,file_mode=0777,sec=ntlmssp
}

install_kernel(){
    kernel_path="$1"
    cp "${kernel_path}/linux-image"* .
    rpm -ivh kernel-* > /root/kernel-install.log
    rm -f *.deb
}

main(){
    
    USERNAME="$1"
    PASSWORD="$2"
    SAMBA_PATH="$3"
    KERNEL_PATH="/mnt/$4/rpm"

    install_deps
    mount_share "$USERNAME" "$PASSWORD" "$SAMBA_PATH"
    if [[ -d "$KERNEL_PATH" ]];then
        install_kernel "$KERNEL_PATH"
        sleep 5
        reboot &
        exit 0
    else
        echo "Kernel folder ${KERNEL_PATH} does not exist"
        exit 1
    fi
}

main $@