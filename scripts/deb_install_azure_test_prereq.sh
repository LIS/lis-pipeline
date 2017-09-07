#!/bin/bash
apt-get -y update
apt-get -y install iperf
apt-get -y install bind9
apt-get install build-essential software-properties-common -y
apt-get -y install python python-pyasn1 python-argparse python-crypto python-paramiko
export DEBIAN_FRONTEND=noninteractive
apt-get -y install mysql-server
apt-get -y install mysql-client