# How to configure Ubuntu 16.04 kernel builder
The kernel build script which this tutorial addresses is found here:
https://github.com/LIS/lis-pipeline/blob/master/scripts/package_building/build_artifacts.sh


## Environment minimum requirements
  - Build OS: Ubuntu Xenial 16.04
  - CPU: minimum 16 cores, more the better.
  - RAM: minimum 4GB, as one kernel build does not use more than 1 or 2 GB of RAM.
  - IO: SSD required, minimum of 5k IOPS. On an Azure VM you can add 12 disks of premium storage and configure them into RAID 0 and you can achieve 60k IOPS. More the better.

## Required packages
  ```bash
    set -xe
    deb_packages=(libncurses5-dev xz-utils libssl-dev libelf-dev bc ccache kernel-package \
        devscripts build-essential lintian debhelper git wget bc fakeroot crudini flex bison \
        asciidoc libdw-dev systemtap-sdt-dev libunwind-dev libaudit-dev libslang2-dev \
        libperl-dev python-dev binutils-dev libiberty-dev liblzma-dev libnuma-dev openjdk-8-jdk \
        libbabeltrace-ctf-dev libbabeltrace-dev pigz pbzip2 python-pip)
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install ${deb_packages[@]}
    sudo pip install envparse
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
    pushd /usr/local/bin
    ln -sf /usr/bin/pbzip2 bzip2
    ln -sf /usr/bin/pbzip2 bunzip2
    ln -sf /usr/bin/pbzip2 bzcat
    ln -sf /usr/bin/pigz gzip
    ln -sf /usr/bin/pigz gunzip
    ln -sf /usr/bin/pigz gzcat
    ln -sf /usr/bin/pigz zcat
    popd
    ```
  - Force a lower compression level on dpkg-deb \-\-build.
    By default, dpkg-deb uses single threaded xz as compression and 9 as a compression level,
    which takes a very long time (5-7 minutes).
    By creating a wrapper to force a parallel compression (gz) and a lower compression level (3 or 4),
    the full process will shorten to orders of a few seconds.
    Before running the script, make sure you create a copy of dpkg-deb.
    Run this script as root and do this only once!
    ```bash
    #!/bin/bash
    set -xe

    dpkg_deb_path=$(which dpkg-deb)
    dpkg_deb_fileinfo=$(file $dpkg_deb_path | grep "ELF" || true)

    if [[ "${dpkg_deb_fileinfo}" == '' ]]; then
        echo "dpkg-deb has been already optimized"
        exit 1
    fi

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

# Configure MSSQL Python driver
  - Install odbc driver:
  ```bash
     sudo apt install -y unixodbc-dev

     sudo -- curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
     sudo curl -o /etc/apt/sources.list.d/mssql-release.list https://packages.microsoft.com/config/ubuntu/16.04/prod.list
     sudo apt-get update
     sudo ACCEPT_EULA=Y apt-get install msodbcsql17

     sudo pip install pyodbc
  ```

  - Change in the '/etc/odbcinst.ini'
  ```bash
     [SQL Server]
     Description=Microsoft ODBC Driver 17 for SQL Server
     Driver=/opt/microsoft/msodbcsql17/lib64/libmsodbcsql-17.1.so.0.1
     UsageCount=1
  ```