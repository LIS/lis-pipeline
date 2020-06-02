#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

# DESCRIPTION
#
#    This bash script is looking for linux-azure and linux-azure-edge proposed
# kernels. The following Ubuntu versions are checked: Trusty, Xenial, Bionic, Focal, Groovy.
# It will take the latest version available for each using apt-cache and compare
# it to latest known version.
#
# -- If there is a new version, an Azure container will be deployed matching the
# distro version and a proposed kernel install will be attempted: -
# ----- If the install is successful, this script will save on a file the info
# that a new kernel has to be validated. The Jenkinsfile
# (Jenkinsfile_ubuntu_azure_kernel_watcher) will get that data and will trigger
# the validation job for the new available kernel
# ----- If the install in the container is not successful, the Jenkinsfile will
# not trigger the validation job. It will wait until the next watcher trigger,
# usually 4 hours.
#
# -- If there isn't a new kernel version available, the Jenkinsfile will
# not trigger the validation job. It will wait until the next watcher trigger,
# usually 4 hours.

function Search_New_Kernel() {
    release=$1
    kernel_type=$2
    old_kernel_version=$3
    if [ ${kernel_type} == "linux-azure" ]; then
        kernel_type_short="_azure"
    elif [ ${kernel_type} == "linux-azure-edge" ]; then
        kernel_type_short="_edge"
    elif [ ${kernel_type} == "linux-image-azure-lts-18.04" ]; then
        kernel_type_short="_azure_lts_1804"
    fi
    latest_kernel=$(sudo apt-cache madison ${kernel_type} 2>/dev/null | grep ${release}-proposed | awk '{print $2}')
    if [ ! -z $latest_kernel ]; then
        echo "Latest $kernel_type Kernel for $release is $latest_kernel"
        echo "Old $kernel_type kernel for $release : $old_kernel_version"
        if [ $old_kernel_version != $latest_kernel ]; then
            echo "Deploying $kernel_type kernel on a $release image container to validate the install"
            Deploy_Container $release $kernel_type
            if [ $? -ne 0 ]; then
                echo "SKIPPING validation for $kernel_type on ${release}. Kernel couldn't be installed!"
                echo "Will try again the install in 4 hours"
            else
                echo "Setting $release $kernel_type for validation testing"
                # Updating the value in latest_versions.sh
                sudo sed -i -e "s|${release}${kernel_type_short}=.*|${release}${kernel_type_short}=${latest_kernel}|g" $VERSION_HISTORY_LOCATION
                sudo sed -i -e "s|${release},${kernel_type},.*|${release},${kernel_type},yes;|g" $VERSION_TO_TEST_LOCATION
            fi
        else
            echo "NO NEW VERSIONS are available for $release proposed $kernel_type kernel"
            sudo sed -i -e "s|${release},${kernel_type},.*|${release},${kernel_type},no;|g" $VERSION_TO_TEST_LOCATION
        fi
    else
        echo "Proposed $kernel_type kernel NOT AVAILABLE for $release"
        sudo sed -i -e "s|${release},${kernel_type},.*|${release},${kernel_type},no;|g" $VERSION_TO_TEST_LOCATION
    fi
}

function Deploy_Container() {
    release=$1
    kernel=$2
    retval=1
    rg_name="ubuntu-${release}-${kernel}"
    container_name="kerneltest"

    az group create --name $rg_name --location "westus2" > /dev/null 2>&1
read -r -d '' cmd_to_send <<- EOM
echo "deb http://archive.ubuntu.com/ubuntu/ ${release}-proposed restricted main multiverse universe" >> /etc/apt/sources.list
export DEBIAN_FRONTEND=noninteractive
apt-get clean all
apt-get -y update
echo "apt-get install -y ${kernel}/${release}"
apt-get install -y ${kernel}/${release}
EOM
    az container create -g $rg_name --name $container_name --image "ubuntu:${release}" --command-line "bash -c '$cmd_to_send'" > /dev/null 2>&1
    sleep 30

    # Get logs
    container_logs=$(az container logs --resource-group $rg_name --name $container_name)
    kernel_count=$(echo $container_logs | grep "The following NEW packages will be installed:" -c)
    if [ $kernel_count -eq 1 ]; then
        retval=0
    else
        echo $container_logs
        echo ""
    fi
    az group delete --name $rg_name --yes

    return $retval
}

# Main
RELEASES=(trusty xenial bionic focal groovy)
VERSION_HISTORY_LOCATION="/home/lisa/latest_versions.sh"
VERSION_TO_TEST_LOCATION="/home/lisa/version_to_test.sh"
. $VERSION_HISTORY_LOCATION

sudo apt clean all
sudo apt -qq update

for release in ${RELEASES[@]}; do
    echo ""
    variable_name="${release}_azure"
    azure_release="${!variable_name}"
    variable_name="${release}_edge"
    edge_release="${!variable_name}"
    variable_name="${release}_azure_lts_1804"
    azure_lts_1804_release="${!variable_name}"

    latest_azure=$(sudo apt-cache madison linux-azure 2>/dev/null | grep ${release}-proposed | awk '{print $3}')
    latest_edge=$(sudo apt-cache madison linux-azure-edge 2>/dev/null | grep ${release}-proposed | awk '{print $3}')
    latest_azure_lts_1804=$(sudo apt search linux-image-azure-lts-18.04 2>/dev/null | grep ${release}-proposed | awk '{print $2}')

    # Check linux-azure proposed kernel for a new version
    Search_New_Kernel $release "linux-azure" $azure_release

    # Check linux-azure-edge proposed kernel for a new version
    Search_New_Kernel $release "linux-azure-edge" $edge_release

    # Check linux-image-azure-lts-18.04 proposed kernel for a new version
    Search_New_Kernel $release "linux-image-azure-lts-18.04" $azure_lts_1804_release
done