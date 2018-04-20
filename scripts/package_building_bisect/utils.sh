function install_deps_rhel {
    #
    # Installing packages required for the build process.
    #
    rpm_packages=(rpm-build rpmdevtools yum-utils ncurses-devel hmaccalc zlib-devel \
    binutils-devel elfutils-libelf-devel openssl-devel wget git ccache bc fakeroot crudini \
    asciidoc audit-devel binutils-devel xmlto bison flex gtk2-devel xz-devel \
    newt-devel openssl-devel xmlto zlib-devel elfutils-devel systemtap-sdt-devel \
    libunwind audit-libs-devel perl-ExtUtils-Embed python-devel numactl-devel \
    java-1.8.0-openjdk-devel)
    sudo yum groups mark install "Development Tools"
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install ${rpm_packages[@]}
}

function install_deps_debian {
    #
    # Installing packages required for the build process.
    #
    deb_packages=(libncurses5-dev xz-utils libssl-dev libelf-dev bc ccache kernel-package \
    devscripts build-essential lintian debhelper git wget bc fakeroot crudini flex bison  \
    asciidoc libdw-dev systemtap-sdt-dev libunwind-dev libaudit-dev libslang2-dev \
    libperl-dev python-dev binutils-dev libiberty-dev liblzma-dev libnuma-dev openjdk-8-jdk \
    libbabeltrace-ctf-dev libbabeltrace-dev)
    DEBIAN_FRONTEND=noninteractive sudo apt-get -y install ${deb_packages[@]}
}

function get_job_number (){
    #
    # Multiply current number of threads with a number
    # Usage:
    #   ./build_artifacts.sh --thread_number x10
    #
    multi="$1"
    cores="$(cat /proc/cpuinfo | grep -c processor)"
    result="$(($cores * $multi))"
    echo ${result%.*}
}
