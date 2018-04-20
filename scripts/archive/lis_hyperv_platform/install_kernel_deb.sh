#!/bin/bash

install_kernel() {
    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} mkdir -p /mnt/{}
    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} mount /dev/{} /mnt/{}

    find /mnt -name "*.deb" | xargs dpkg -i

    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} umount /mnt/{}
    lsblk | grep rom | cut -d ' ' -f 1 | xargs -I {} rm -rf /mnt/{}
}

main() {
    apt update
    apt -y install binutils at dos2unix
    systemctl enable atd.service
    install_kernel
    cp -rf /home/ubuntu/.ssh/authorized_keys /
    sed -i 's%#AuthorizedKeysFile.*%AuthorizedKeysFile /authorized_keys%' /etc/ssh/sshd_config
    shutdown -h now
}

main

exit 0
