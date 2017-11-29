#!/bin/bash
#
#  Script to take a VM template and make it our own
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
#
#  Load our secrets.sh
#
source /tmp/secrets.sh

#
#  Perform redhat subscription manager stuff.
#
if [ -f /sbin/subscription-manager ] ;
  then
  echo "RedHat specific configuration."
  echo " -- configuring subscription-manager."
  echo " -- $REDHAT_SUBSCRIPTION_ID:$REDHAT_SUBSCRIPTION_PW"

  subscription-manager register --username $REDHAT_SUBSCRIPTION_ID --password $REDHAT_SUBSCRIPTION_PW --auto-attach
  subscription-manager repos --enable rhel-7-server-optional-rpms 
  subscription-manager repos --enable rhel-7-server-extras-rpms;
fi;


#
#  Add the test user
#

if [ -f /usr/bin/dpkg ] ;
  then
    echo "This is a dpkg machine"
    useradd -d /home/$TEST_USER_ACCOUNT_NAME -s /bin/bash -G sudo -m $TEST_USER_ACCOUNT_NAME -p $TEST_USER_ACCOUNT_PASS
    passwd $TEST_USER_ACCOUNT_NAME << PASSWD_END
$TEST_USER_ACCOUNT_PASS
$TEST_USER_ACCOUNT_PASS
PASSWD_END
else
    echo "This is an RPM-based machine"
    #
    #  Add the test user
    useradd -d /home/$TEST_USER_ACCOUNT_NAME -s /bin/bash -G wheel -m $TEST_USER_ACCOUNT_NAME -p $TEST_USER_ACCOUNT_PASS 
    passwd $TEST_USER_ACCOUNT_NAME << PASSWD_END
$TEST_USER_ACCOUNT_PASS
$TEST_USER_ACCOUNT_PASS
PASSWD_END
fi;

#
#  Find out what kind of system we're on
#
if [ -f /usr/bin/dpkg ] ;
  then
    echo "This is a dpkg machine"
    rm -f /var/lib/dpkg/lock
    dpkg --configure -a
    apt --fix-broken -y install

    apt-get -y install git
    #  Let's grab the dpkg puppet installer.
    #  TODO: do i really need wget here?
    export is_rpm=0;
else
    echo "This is an RPM-based machine"
    yum -y install wget
    yum -y install git
    # Adding in Epel
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 
    rpm -i epel-release-latest-7.noarch.rpm 
    yum install -y epel-release  
    export is_rpm=1;
fi

# 
# Retrieve our depot.
#
mkdir /HIPPEE

framework_scripts_path="/HIPPEE/Framework-Scripts"
#if ! [ -d $framework_scripts_path ]; then
  git clone https://github.com/FawcettJohnW/Framework-Scripts.git $framework_scripts_path
#fi;

chown -R mstest /HIPPEE

#
# REVISED: I don't believe the following line is really necessary.
#   The check above determines if we have already pulled the depot, if this is the case, we don't get new code
#   to -that- location, but the following line just clones to our relative path.  When we later -use- the scripts,
#   we always assume the $framework_scripts_path ... so the following -might- be cloned but won't be cloned where
#   want it.
#
#git clone http://github.com/FawcettJohnW/Framework-Scripts.git

#
# Copy existing secrets files.
#
if [ -f /tmp/secrets.ps1 ] ;
  then 
  echo "Updating framework with preconfigured secrets.ps1"
  cp /tmp/secrets.ps1 $framework_scripts_path/secrets.ps1
fi;

if [ -f /tmp/secrets.sh ] ;
  then 
  echo "Updating framework with preconfigured secrets.sh"
  cp /tmp/secrets.sh $framework_scripts_path/secrets.sh
fi;

#
#  Legacy Main steps...
#
if [ $is_rpm == 0 ]
  then
    echo "DEB-based system"
    echo "Precursors."

apt-get -y update
apt-get -y install iperf
apt-get -y install bind9
apt-get install build-essential software-properties-common -y
apt-get -y install python python-pyasn1 python-argparse python-crypto python-paramiko
export DEBIAN_FRONTEND=noninteractive
apt-get -y install mysql-server
apt-get -y install mysql-client
    
cp /etc/apt/sources.list /etc/apt/sources.list.orig
cat << NEW_SOURCES > /etc/apt/sources.list.orig
deb  http://deb.debian.org/debian stretch main
deb-src  http://deb.debian.org/debian stretch main

deb  http://deb.debian.org/debian stretch-updates main
deb-src  http://deb.debian.org/debian stretch-updates main

deb http://security.debian.org/ stretch/updates main
deb-src http://security.debian.org/ stretch/updates main
NEW_SOURCES
    #
    #  Make sure things are consistent
    apt-get -y update
    apt-get install -y curl
    apt-get install -y dnsutils
    apt-get install -y apt-transport-https

    wget http://ftp.us.debian.org/debian/pool/main/o/openssl1.0/libssl1.0.2_1.0.2l-2_amd64.deb
    dpkg -i ./libssl1.0.2_1.0.2l-2_amd64.deb

    #
    #  Set up the repos to look at and update
    dpkg -l linux-{image,headers}-* | awk '/^ii/{print $2}' | egrep '[0-9]+\.[0-9]+\.[0-9]+' | grep -v $(uname -r | cut -d- -f-2) | xargs sudo apt-get -y purge
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
    curl https://packages.microsoft.com/config/ubuntu/14.04/prod.list | tee /etc/apt/sources.list.d/microsoft.list
    apt-get -y update

    #
    #  Install PowerShell.  Right now, we have to manually install a downlevel version, but we install the current one
    #  first so all the dependancies are satisfied.
    # apt-get install -y powershell
    #
    #  This package is in a torn state
    wget http://launchpadlibrarian.net/201330288/libicu52_52.1-8_amd64.deb
    dpkg -i libicu52_52.1-8_amd64.deb

    #
    #  Install and remove PS
    apt-get install -y powershell

    #
    #  Download and install the beta 2 version
    export download_1404="https://github.com/PowerSahell/PowerShell/releases/download/v6.0.0-beta.2/powershell_6.0.0-beta.2-1ubuntu1.14.04.1_amd64.deb"
    export download_1604="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell_6.0.0-beta.2-1ubuntu1.16.04.1_amd64.deb"
    wget $download_1604

    export pkg_name=`echo $download_1604 | sed -e s/.*powershell/powershell/`
    dpkg -r powershell
    wget http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu55_55.1-7_amd64.deb
    dpkg -i libicu55_55.1-7_amd64.deb
    dpkg -i $pkg_name

    #
    #  Install OMI and PSRP
    apt-get install -y omi
    apt-get install -y omi-psrp-server

    #
    #  Need NFS
    apt-get install -y nfs-common

    #
    #  Enable the HTTPS port and restart OMI
    sed -e s/"httpsport=0"/"httpsport=0,443"/ < /etc/opt/omi/conf/omiserver.conf > /tmp/x
    /bin//cp /tmp/x /etc/opt/omi/conf/omiserver.conf
    /opt/omi/bin/omiserver -s
    /opt/omi/bin/omiserver -d

    #
    #  Allow basic auth and restart sshd
    sed -e s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ < /etc/ssh/sshd_config > /tmp/x
    /bin/cp /tmp/x /etc/ssh/sshd_conf
    service ssh restart
   
    #
    #  Set up runonce and copy in the right script
    if ! [ -d "/HIPPEE/runonce.d" ]; then
        mkdir /HIPPEE/runonce.d /HIPPEE/runonce.d/ran
    fi
## Unhooking the runonce.d so that we can place other things there in the future.
## to use, simply connect in and copy as shown below.
#    cp Framework-Scripts/update_and_copy.ps1 runonce.d/
    
    #
    #  Tell cron to run the runonce at reboot
    echo "@reboot root /HIPPEE/Framework-Scripts/runonce.ps1" >> /etc/crontab
    apt-get install -y ufw
    ufw allow 443
    ufw allow 5986
    /opt/omi/bin/omiserver -d
else
    echo "RPM-based system"
wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 
rpm -i epel-release-latest-7.noarch.rpm 
yum install -y epel-release 

    echo "Precursors"
yum -y install wget
rpm -Uvh http://linux.mirrors.es.net/fedora-epel/7/x86_64/i/iperf-2.0.8-1.el7.x86_64.rpm
yum -y localinstall https://dev.mysql.com/get/mysql57-community-release-el7-9.noarch.rpm
yum -y install mysql-community-server
yum -y groupinstall --skip-broken "Development Tools"
yum -y install python 
yum -y install python-pyasn1
yum -y install python-argparse
yum -y install python-crypto
yum -y install python-paramiko

    #
    #  Make sure we have the tools we need
    yum install -y yum-utils
    yum install -y bind-utils

    #
    #  Clean up disk space
    package-cleanup -y --oldkernels --count=2

    #
    #  Set up our repo and update
    curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
    yum update -y

    #
    #  See above about PowerSHell
    # yum install -y powershell
    yum install -y powershell
    yum erase -y powershell
    export download_normal="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell-6.0.0_beta.2-1.el7.x86_64.rpm"
    export doenload_suse="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell-6.0.0_beta.2-1.suse.42.1.x86_64.rpm"
    wget $download_normal
    rpm -i $download_normal

    #
    #  OMI and PSRP
    yum install -y omi
    yum install -y omi-psrp-server

    #
    #  Need NFS
    yum install -y nfs-utils

    #
    #  Set up HTTPS and restart OMI
    sed -e s/"httpsport=0"/"httpsport=0,443"/ < /etc/opt/omi/conf/omiserver.conf > /tmp/x
    /bin/cp /tmp/x /etc/opt/omi/conf/omiserver.conf
    /opt/omi/bin/omiserver -s
    /opt/omi/bin/omiserver -d

    #
    #  Allow basic auth and restart sshd
    sed -e s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ < /etc/ssh/sshd_config > /tmp/x
    /bin/cp /tmp/x /etc/ssh/sshd_conf
    systemctl stop sshd
    systemctl start sshd

    #
    #  Set up runonce
    mkdir /HIPPEE/runonce.d /HIPPEE/runonce.d/ran

## Unhooking the runonce.d so that we can place other things there in the future.
## to use, simply connect in and copy as shown below.
    #
    #    cp Framework-Scripts/update_and_copy.ps1 runonce.d/
    #
    #
    #  Tell cron to run the runonce at reboot
    echo "@reboot root /HIPPEE/Framework-Scripts/runonce.ps1" >> /etc/crontab

    #
    #  Make sure 443 is allowed through the firewall
    systemctl start firewalld
    firewall-cmd --zone=public --add-port=443/tcp --permanent
    systemctl stop firewalld
    systemctl start firewalld
    /opt/omi/bin/omiserver -d
fi

#
# TODO: Is this needed for ALL pipelines?
#
if [ -f /etc/motd ] 
  then
    mv /etc/motd /etc/motd_before_ms_kernel
fi

#
# TODO: Do we need this password reset?
#

passwd mstest << PASSWD_END
$TEST_USER_ACCOUNT_PASS
$TEST_USER_ACCOUNT_PASS
PASSWD_END

cat << "MOTD_EOF" > /etc/motd
*************************************************************************************

    WARNING   WARNING   WARNING   WARNING   WARNING   WARNING   WARNING   WARNING
    
      THIS IS AN EXPERIMENTAL COMPUTER.  IT IS NOT INTENDED FOR PRODUCTION USE


                 Microsoft Authorized Employees and Partners ONLY!

                   Please wave your badge in front of the screen

     If you are authorized to use this machine, we welcome you and invite your
   feedback through the established channels.  If you're not authorized, please
   don't tell anybody about this.  It really annoys the bosses when things like
   that happen.


   Welcome to the Twilight Zone.                                      Let's Rock.
*************************************************************************************
MOTD_EOF

#
#  Perform redhat subscription manager stuff.
#
if [ -f /sbin/subscription-manager ] ;
  then
  echo "RedHat specific configuration."
  echo " -- Removing configuration for subscription-manager."
  subscription-manager remove --all
fi;
