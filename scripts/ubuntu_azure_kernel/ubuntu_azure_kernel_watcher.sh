#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

RELEASES=(trusty xenial bionic cosmic)
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

    latest_azure=$(sudo apt-cache madison linux-azure | grep ${release}-proposed | awk '{print $3}')
    latest_edge=$(sudo apt-cache madison linux-azure-edge | grep ${release}-proposed | awk '{print $3}')
    if [ ! -z $latest_azure ]; then
        echo "Latest Azure Kernel for $release is $latest_azure"
        echo "Old Azure kernel for $release : $azure_release"
        if [ $azure_release != $latest_azure ]; then
            echo "We have a new kernel. Triggering $release azure kernel testing"
            # Updating the value in latest_versions.sh
            sudo sed -i -e "s|${release}_azure=.*|${release}_azure=${latest_azure}|g" $VERSION_HISTORY_LOCATION
            sudo sed -i -e "s|${release},linux-azure,.*|${release},linux-azure,yes;|g" $VERSION_TO_TEST_LOCATION
        else
            echo "No new proposed azure kernel found for $release"
            sudo sed -i -e "s|${release},linux-azure,.*|${release},linux-azure,no;|g" $VERSION_TO_TEST_LOCATION
        fi
    else
        echo "Proposed Azure kernel not available for $release"
        sudo sed -i -e "s|${release},linux-azure,.*|${release},linux-azure,no;|g" $VERSION_TO_TEST_LOCATION
    fi

    if [ ! -z $latest_edge ]; then
        echo "Latest Edge Kernel for $release is $latest_edge"
        echo "Old Edge kernel for $release : $edge_release"
        if [ $edge_release != $latest_edge ]; then
            echo "We have a new kernel. Triggering $release edge kernel testing"
            # Updating the value in latest_versions.sh
            sudo sed -i -e "s|${release}_edge=.*|${release}_edge=${latest_edge}|g" $VERSION_HISTORY_LOCATION
            sudo sed -i -e "s|${release},linux-azure-edge,.*|${release},linux-azure-edge,yes;|g" $VERSION_TO_TEST_LOCATION
        else
            echo "No new proposed edge kernel found for $release"
            sudo sed -i -e "s|${release},linux-azure-edge,.*|${release},linux-azure-edge,no;|g" $VERSION_TO_TEST_LOCATION
        fi
    else
        echo "Proposed Azure edge kernel not available for $release"
        sudo sed -i -e "s|${release},linux-azure-edge,.*|${release},linux-azure-edge,no;|g" $VERSION_TO_TEST_LOCATION
    fi
done