#!/bin/bash

install_kernel() {
    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} mkdir -p /mnt/{}
    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} mount /dev/{} /mnt/{}

    find /mnt -name "*.rpm" | xargs rpm -ivh --force --nodeps

    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} umount /mnt/{}
    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} rm -rf /mnt/{}
}

main() {
    yum -y install binutils at dos2unix
    systemctl enable atd.service
    ssh-keygen
    cat /home/centos/.ssh/authorized_keys > /root/.ssh/authorized_keys
    sed -i 's%#PermitRootLogin Yes%PermitRootLogin Yes%' /etc/ssh/sshd_config
    install_kernel
    sed -i 's%GRUB_DEFAULT=.*%GRUB_DEFAULT=0%' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    reboot
}

main

exit 0
