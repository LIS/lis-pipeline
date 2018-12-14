# How to configure Ubuntu 16.04 meta slave

## Environment minimum requirements
  - Build OS: Ubuntu Xenial 16.04
  - CPU: minimum 2 cores, more the better.
  - RAM: minimum 2GB, as the meta slave does not consume too many resources.

## Required packages
  ```bash
    set -xe
    deb_packages=(crudini cifs-utils python-pip)
    sudo DEBIAN_FRONTEND=noninteractive apt install -y ${deb_packages[@]}
    sudo pip install envparse
  ```

## Azure integration
  - Packages required
    ```bash
    #!/bin/bash
    set -xe
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
        sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
    curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

    sudo apt install -y apt-transport-https jq
    sudo apt-get update
    sudo apt-get install azure-cli
    ```
