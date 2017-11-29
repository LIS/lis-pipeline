#!/bin/bash

function GetOSVersion {
    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s | head -c 1)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    
    #
    # If lsb_release is not installed, we should be able to detect Debian OS
    #
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

function is_rhel {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi
    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleServer" ]
}

function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}

function copy_ssh_keys {
    if [[ -d "/tmp/ssh" ]]; then
        if [[ ! -d "/root/.ssh" ]]; then
            mkdir "/root/.ssh"
        fi
        cp /tmp/ssh/* "/root/.ssh"
        cat *.pub > "/root/.ssh/authorized_keys"
        chmod 600 /root/.ssh/*
        chmod 700 "/root/.ssh"
        rm -Rf "/tmp/ssh"
    else 
        echo "The ssh keys are missing"
    fi
}

function configure_ssh {
    echo "Uncommenting #Port 22..."
    sed -i -e 's/#Port/Port/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment Port succeeded."
    else
        echo "Error: Uncomment #Port failed."
    fi

    echo "Uncommenting #Protocol 2..."
    sed -i -e 's/#Protocol/Protocol/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment Protocol succeeded."
    else
        echo "Error: Uncomment #Protocol failed."
    fi

    echo "Uncommenting #PermitRootLogin..."
    sed -i -e 's/#PermitRootLogin/PermitRootLogin/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #PermitRootLogin succeeded."
    else
        echo "Error: Uncomment #PermitRootLogin failed."
    fi

    echo "Uncommenting RSAAuthentication..."
    sed -i -e 's/#RSAAuthentication/RSAAuthentication/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #RSAAuthentication succeeded."
    else
        echo "Error: Uncomment #RSAAuthentication failed."
    fi

    echo "Uncommenting PubkeyAuthentication..."
    sed -i -e 's/#PubkeyAuthentication/PubkeyAuthentication/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #PubkeyAuthentication succeeded."
    else
        echo "Error: Uncomment #PubkeyAuthentication failed."
    fi

    echo "Uncommenting AuthorizedKeysFile..."
    sed -i -e 's/#AuthorizedKeysFile/AuthorizedKeysFile/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #AuthorizedKeysFile succeeded."
    else
        echo "Error: Uncomment #AuthorizedKeysFile failed."
    fi

    echo "Uncommenting PasswordAuthentication..."
    sed -i -e 's/#PasswordAuthentication/PasswordAuthentication/g' /etc/ssh/sshd_config
    if [ $? -eq 0 ]
    then
        echo "Uncomment #PasswordAuthentication succeeded."
    else
        echo "Error: Uncomment #PasswordAuthentication failed."
    fi

    echo "Allow root login..."
    sed -i -e 's/PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
}

function install_lisa_req_ubuntu {
    # Install Packages
    UBU_REQ="kdump-tools openssh-server tofrodos dos2unix ntp open-iscsi iperf gpm vlan iozone3 
    multipath-tools expect libaio-dev libattr1-dev stressapptest git mdadm automake libtool
    bridge-utils btrfs-tools libkeyutils-dev xfsprogs reiserfsprogs sysstat numactl nfs-client  
    linux-cloud-tools-common linux-tools-`uname -r` linux-cloud-tools-`uname -r`"
    UBU_INSTALLED="dosfstools gcc at zip make wget pkg-config build-essential bc python3 pciutils parted
    netcat squashfs-tools"
	
    apt-get -y install $UBU_REQ 
    apt-get -y install $UBU_INSTALLED 
    # Configure Multipath		
    if [ -e /etc/multipath.conf ]; then
        rm /etc/multipath.conf
    fi	
    echo -e "blacklist {\n\tdevnode \"^sd[a-z]\"\n}" >> /etc/multipath.conf
    service multipath-tools restart
    # Configure ssh	
    configure_ssh
    copy_ssh_keys	
    systemctl enable ssh.service
}

function install_lisa_req_rhel {
    # Install Packages
    CENT_REQ="dos2unix at net-tools gpm bridge-utils ntp crash bc 
    dosfstools selinux-policy-devel libaio-devel libattr-devel keyutils-libs-devel  
    nano device-mapper-multipath expect sysstat git wget mdadm numactl 
    python3 nfs-utils omping nc squashfs-tools hyperv-daemons"	
    CENT_INSTALLED="openssh-server btrfs-progs xfsprogs gcc gcc-c++ autoconf automake parted kexec-tools
    pciutils"
	
    yum groups mark install "Development Tools"
    yum groups mark convert "Development Tools"
    yum -y groupinstall "Development Tools"	
    yum -y install $CENT_REQ 
    yum -y install $CENT_INSTALLED	
    systemctl daemon-reload
    systemctl start hypervkvpd
    systemctl start atd
    systemctl enable atd	
    # Configure ssh
    configure_ssh
    copy_ssh_keys
    systemctl enable sshd.service
}

function install_lisa_req { 
    if is_rhel ; then
        install_lisa_req_rhel
    elif is_ubuntu ; then
        install_lisa_req_ubuntu
    fi
}

install_lisa_req
