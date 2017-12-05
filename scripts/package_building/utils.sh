# Copyright 2017 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

function get_os_version {
    #
    # Determine what OS is running
    #  
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_vendor=`sw_vers -productName`
        os_release=`sw_vers -productVersion`
        os_update=${os_release##*.}
        os_release=${os_release%.*}
        os_package=""
        os_package_manager=""
        if [[ "$os_release" =~ "10.7" ]]; then
            os_codename="lion"
        elif [[ "$os_release" =~ "10.6" ]]; then
            os_codename="snow leopard"
        elif [[ "$os_release" =~ "10.5" ]]; then
            os_codename="leopard"
        elif [[ "$os_release" =~ "10.4" ]]; then
            os_codename="tiger"
        elif [[ "$os_release" =~ "10.3" ]]; then
            os_codename="panther"
        else
            os_codename=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_vendor=$(lsb_release -i -s)
        os_release=$(lsb_release -r -s)
        os_update=""
        os_package="rpm"
        os_package_manager="yum"
        if [[ "Debian,Ubuntu,LinuxMint,Parrot" =~ $os_vendor ]]; then
            os_package="deb"
            os_package_manager="apt"
        elif [[ "SUSE LINUX" =~ $os_vendor ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_vendor="openSUSE"
            fi
        elif [[ $os_vendor == "openSUSE project" ]]; then
            os_vendor="openSUSE"
        elif [[ $os_vendor =~ Red.*Hat ]]; then
            os_vendor="Red Hat"
        fi
        os_codename=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then

        #
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        #
        os_codename=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_vendor=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_codename=${ver#*|}
                os_release=${ver%|*}
                os_update=${os_release##*.}
                os_release=${os_release%.*}
                break
            fi
            os_vendor=""
        done
        os_package="rpm"
        os_package_manager="yum"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_vendor="SUSE LINUX"
            else
                os_vendor=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_codename=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_release=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_update=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_vendor=""
        done
        os_package="rpm"
        os_package_manager="TODO: suse package manager"

    #
    # If lsb_release is not installed, we should be able to detect Debian OS
    #
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_vendor="Debian"
        os_package="deb"
        os_package_manager="apt"
        os_codename=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_release=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi  
    if [[ "$os_vendor" == "Red Hat" ]] || [[ "$os_vendor" == "CentOS" ]];then
        os_family="rhel"
    elif [[ "$os_vendor" == "Debian" ]] || [[ "$os_vendor" == "Ubuntu" ]];then
        os_family="debian"
    elif [[ "$os_vendor" == "openSUSE" ]];then
        os_family="suse"
    fi
    
    echo "os_FAMILY=$os_family os_VENDOR=$os_vendor os_RELEASE=$os_release os_UPDATE=$os_update \
os_PACKAGE=$os_package os_PACKAGE_MANAGER=$os_package_manager os_CODENAME=$os_codename"
}

split_string() {
    string="$1"
    del="$2"

    while test "${string#*$del}" != "$string" ; do
        split_str="${split_str} ${string%%$del*}"
        string="${string#*$del}"
    done
    split_str="${split_str# *} ${string}"
    echo "$split_str"
}

exec_with_retry2 () {
    MAX_RETRIES=$1
    INTERVAL=$2

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        eval '${@:3}' || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

exec_with_retry () {
    CMD=$1
    MAX_RETRIES=${2-10}
    INTERVAL=${3-0}

    exec_with_retry2 $MAX_RETRIES $INTERVAL $CMD
}

pushd() {
    command pushd "$@" > /dev/null
}

popd() {
    command popd "$@" > /dev/null
}

get_branch_from_ini() {
    git_branch="$1"
    ini_file="$2"
    
    branch=`crudini --get "$ini_file" BRANCHES $git_branch`||true
    if [[ "$branch" == "" ]];then
        branch="$git_branch"
    fi
    echo $branch
}

copy_artifacts() {
    artifacts_folder=$1
    destination_path=$2
    
    rpm_exists="$(ls $artifacts_folder/*.rpm || true)"
    if [[ "$rpm_exists" != "" ]];then
        cp "$artifacts_folder"/*.rpm "$destination_path"
    fi
    deb_exists="$(ls $artifacts_folder/*.deb || true)"
    if [[ "$deb_exists" != "" ]];then
        cp "$artifacts_folder"/*.deb "$destination_path"
    fi
}

check_destination_dir() {
    dest_folder=$1
    os_package=$2
    
    if [[ ! -d "$dest_folder" ]] || [[ ! -d "${dest_folder}/$os_package" ]];then
        mkdir -p "${dest_folder}/$os_package"
        echo "${dest_folder}/$os_package"
    else
        index=1
        while [[ -d "${dest_folder}-$index" ]] && [[ -d "${dest_folder}-${index}/$os_package" ]];do
            let index=index+1
        done
        mkdir -p "${dest_folder}-$index/$os_package"
        echo "${dest_folder}-$index/$os_package"
    fi
}

get_destination_path() {
    source_path="$1"
    base_dest_path="$2"
    os_package="$3"
    git_tag="$4"

    pushd "$source_path"
    kernel_version="$(make kernelversion)"
    kernel_version="${kernel_version%-*}"
    popd
    destination_path="$base_dest_path/msft-${kernel_version}-${git_tag}-$(date +'%d%m%Y')"
    destination_path="$(check_destination_dir $destination_path $os_package)"

    echo "$destination_path"
}

get_git_tag(){
    source_path="$1"
    branch="$2"

    if [[ "$branch" == "" ]];then
        branch="HEAD"
    fi
    pushd "$source_path"
    git_tag="$(git rev-parse $branch)"
    git_tag="${git_tag:0:7}"
    popd
    echo "$git_tag"
}


get_stable_branches() {
    git_dir="$1"

    pushd "$git_dir"
    branches="$(git branch --all)"
    for branch in $branches;do
        if [[ "$branch" != "${branch#remotes/*}" ]] && [[ "$branch" != "${branch%*.y}" ]];then
            branch="${branch#remotes/*}"
            small_branch="${branch#origin/*}"
            tag="$(get_git_tag $git_dir $branch)"

            result="${result},${small_branch}#${tag}"
        fi
    done
    popd
    echo "${result#,*}"
}

get_latest_stable_branch() {
    git_dir="$1"
    
    branches="$(get_stable_branches $git_dir)"
    echo "${branches##*,}"
}

get_latest_unstable_branch() {
    git_dir="$1"

    pushd "$git_dir"
    branches="$(git branch --all)"
    for branch in $branches;do
        if [[ "$branch" != "${branch#remotes/*}" ]] && [[ "$branch" == "${branch%*.y}" ]];then
            branch="${branch#remotes/*}"
            small_branch="${branch#origin/*}"
            tag="$(get_git_tag $git_dir $branch)"

            result="${small_branch}#${tag}"
        fi
    done
    popd
    echo "${result}"
}
