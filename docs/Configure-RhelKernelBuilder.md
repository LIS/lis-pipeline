# How to configure RHEL /CentOS 7.x kernel builder
The kernel build script which this tutorial addresses is found here:
https://github.com/LIS/lis-pipeline/blob/master/scripts/package_building/build_artifacts.sh


## Environment minimum requirements
  - Build OS: CentOS 7.x or RHEL 7.x
  - CPU: minimum 16 cores, more the better.
  - RAM: minimum 4GB, as one kernel build does not use more than 1 or 2 GB of RAM.
  - IO: SSD required, minimum of 5k IOPS. On an Azure VM you can add 12 disks of premium storage and configure them into RAID 0 and you can achieve 60k IOPS. More the better.

## Required packages
  - Packages required:
  ```bash
    set -xe
    rpm_packages=(rpm-build rpmdevtools yum-utils ncurses-devel hmaccalc zlib-devel \ 
        binutils-devel elfutils-libelf-devel openssl-devel wget git ccache bc fakeroot \
        asciidoc binutils-devel xmlto bison flex gtk2-devel xz-devel numactl-devel \
        newt-devel openssl-devel xmlto zlib-devel crudini pigz pbzip2)

    # epel repo required for crudini, pigz and pbzip2
    sudo rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

    sudo yum groups mark install "Development Tools"
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install ${rpm_packages[@]}
  ```

## Optimizations
  - Configure the number of cores for the make command to be times 2 or 3 the number of physical cores.
    This will speed up the build process and the only bottleneck will be the IOPS.
  - Use ccache: https://ccache.samba.org/
      ```bash
      PATH="/usr/lib/ccache:"$PATH
      ```
  - Make tar use parallel archivers. Run this script as root!
    ```bash
    #!/bin/bash
    set -xe
    pushd /bin
    ln -sf /bin/pbzip2 bzip2
    ln -sf /bin/pbzip2 bunzip2
    ln -sf /bin/pbzip2 bzcat
    ln -sf /bin/pigz gzip
    ln -sf /bin/pigz gunzip
    ln -sf /usr/bin/pigz zcat
    popd
    ```