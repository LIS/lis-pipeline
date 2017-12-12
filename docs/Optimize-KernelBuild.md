# How to optimize the Linux kernel build

The kernel build script which this tutorial addresses is found here:
https://github.com/LIS/lis-pipeline/blob/master/scripts/package_building/build_artifacts.sh


## Environment minimum requirements
  - Build OSes: Ubuntu Xenial 16.04 or CentOS 7.
  - CPU: minimum 16 cores, more the better.
  - RAM: minimum 4GB, as one kernel build does not use more than 1 or 2 GB of RAM.
  - IO: SSD required, minimum of 5k IOPS. On an Azure VM you can add 12 disks of premium storage and configure them into RAID 0 and you can achieve 60k IOPS. More the better.

## Required packages
### Debian
  - Packages required:
  ```bash
    set -xe
    deb_packages=(libncurses5-dev xz-utils libssl-dev libelf-dev bc ccache kernel-package \
        devscripts build-essential lintian debhelper git wget bc fakeroot flex bison asciidoc \
        pigz pbzip2)
    DEBIAN_FRONTEND=noninteractive sudo apt-get -y install ${deb_packages[@]}
  ```

### CentOS
  - Packages required:
  ```bash
    set -xe
    rpm_packages=(rpm-build rpmdevtools yum-utils ncurses-devel hmaccalc zlib-devel \ 
        binutils-devel elfutils-libelf-devel openssl-devel wget git ccache bc fakeroot \
        asciidoc audit-devel binutils-devel xmlto bison flex gtk2-devel libdw-devel libelf-devel \
        xz-devel libnuma-devel newt-devel openssl-devel xmlto zlib-devel pigz pbzip2)
    sudo yum -y install epel-release #required for pigz and pbzip2
    sudo yum groups mark install "Development Tools"
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install ${rpm_packages[@]}
  ```

## Optimizations
### Generic optimizations
  - Configure the number of cores for the make command to be times 2 or 3 the number of physical cores.
    This will speed up the build process and the only bottleneck will be the IOPS.
  - Use ccache: https://ccache.samba.org/
      ```bash
      PATH="/usr/lib/ccache:"$PATH
      ```
  - Make tar use parallel archivers
    ```bash
    set -xe
    sudo pushd /usr/local/bin
    sudo ln -s /usr/bin/pbzip2 bzip2
    sudo ln -s /usr/bin/pbzip2 bunzip2
    sudo ln -s /usr/bin/pbzip2 bzcat
    sudo ln -s /usr/bin/pigz gzip
    sudo ln -s /usr/bin/pigz gunzip
    sudo ln -s /usr/bin/pigz gzcat
    sudo ln -s /usr/bin/pigz zcat
    popd
    ```

### Debian
  - Force a lower compression level on dpkg-deb \-\-build.
    By default, dpkg-deb uses single threaded xz as compression and 9 as a compression level,
    which takes a very long time (5-7 minutes).
    By creating a wrapper to force a parallel compression (gz) and a lower compression level (3 or 4),
    the full process will shorten to orders of a few seconds.
    Before running the script, make sure you create a copy of dpkg-deb.
    Run this script as root!
    ```bash
    set -xe

    dpkg_deb_path=$(which dpkg-deb)
    cp $dpkg_deb_path "${dpkg_deb_path}-original"
    cat > $dpkg_deb_path <<- EOM
    #!/bin/bash
    set -xe
    args=\$@
    if [[ \$@ == *"--build"* ]]; then
        args="-z3 -Zgzip \$args"
    fi
    dpkg-deb-original \$args
    EOM
    chmod 777 $dpkg_deb_path
    ```

### RHEL
TBD.