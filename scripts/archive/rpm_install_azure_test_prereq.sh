#!/bin/bash
rpm -Uvh http://linux.mirrors.es.net/fedora-epel/7/x86_64/i/iperf-2.0.8-1.el7.x86_64.rpm       
yum -y localinstall https://dev.mysql.com/get/mysql57-community-release-el7-9.noarch.rpm
yum -y install mysql-community-server
yum -y groupinstall "Development Tools"
yum -y install bind bind-utils 
yum -y install python python-pyasn1
yum -y install python-argparse 
yum -y install python-crypto 
yum -y install python-paramiko