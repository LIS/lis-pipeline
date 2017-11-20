#!/bin/bash

install_deps(){
    apt-get -y install samba cifs-utils openssh-server
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
    dpkg -i linux-image* > /root/kernel-install.log
    rm -f *.deb
}

main(){
    
    USERNAME="<username>"
    PASSWORD="<password>"
    SAMBA_PATH="<samba_path>"
    KERNEL_PATH="/mnt/<kernel_path>/deb"

    install_deps
    mount_share "$USERNAME" "$PASSWORD" "$SAMBA_PATH"
    if [[ -d "$KERNEL_PATH" ]];then
        install_kernel "$KERNEL_PATH"
    fi
    sleep 5 && reboot &
    exit 0
}

main $@