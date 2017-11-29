#!/usr/bin/powershell
#
#  Copy the latest kernel build from the secure share to the local directory,
#  then install it, set the default kernel, switch out this script for the
#  secondary boot replacement, and reboot the machine.
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $pkg_mount_point="Undefined",
    [Parameter(Mandatory=$false)] [string] $pkg_mount_source="Undefined",

    [Parameter(Mandatory=$false)] [string] $pkg_resourceGroup="smoke_output_resource_group",
    [Parameter(Mandatory=$false)] [string] $pkg_storageaccount="smoketestoutstorageacct",
    [Parameter(Mandatory=$false)] [string] $pkg_container="last-build-packages",

    [Parameter(Mandatory=$false)] [string] $pkg_location="westus"
)
cd /HIPPEE/Framework-Scripts
git pull

. "/HIPPEE/Framework-Scripts/secrets.ps1"

#
#  Clean up
$pkg_mount_point=$pkg_mount_point.Trim()
$pkg_mount_source=$pkg_mount_source.Trim()
$pkg_resourceGroup=$pkg_resourceGroup.Trim()
$pkg_storageaccount=$pkg_storageaccount.Trim()
$pkg_container=$pkg_container.Trim()
$pkg_location=$pkg_location.Trim()

$global:isHyperV = $false
$global:o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$global:pw=convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS"
$global:cred=new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$global:pw
$global:session=$null
function ErrOut([string] $failPoint) {
    #
    #  Not really sure what happened.  Better let a human have a look...
    #
    phoneHome("FAILURE in copy_kernel.ps1!!  Kernel was not installed and the system may be in an inconsistent state.")
    phoneHome("Shutting down the system for examination")

    #
    #  Call the reporting script directly, passing in the failure point.  This will cause the install to fail above
    #
    ./report_kernel_version.ps1 $failure_point

    sync
    sync
    sync
    # halt
    exit 1
}

get-pssession | remove-pssession
$agents = pidof omiagent
#
#  Have to specify full path here to avoid
foreach ($agent in $agents) {
Stop-Process -id 
    @(/bin/kill -9 $agent)
}

function callItIn($c, $m) {
    $output_path="c:\temp\progress_logs\$c"

    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {
Write-Output $m
    if ($global:isHyperV -eq $true) {

        if ($global:session -eq $null) {
            write-output "*** Restarting the PowerShell session!" | out-file -Append /opt/microsoft/borg_progress.log
            get-pssession | remove-pssession
            $global:session=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $global:cred -authentication Basic -SessionOption $global:o
        }

        invoke-command -session $global:session -ScriptBlock ${function:callItIn} -ArgumentList $c,$m

        $m | out-file -Append /opt/microsoft/borg_progress.log
    } else {
        $m | out-file -Append /opt/microsoft/borg_progress.log
    }
}

function callVersionIn($f,$m) {
    $output_path=$f

    $m | out-file -Force $output_path
    return
}


function phoneVersionHome($m) {

    $outFile = "c:\temp\expected_version_deb"
    if (Test-Path /bin/rpm) {
        $outFile = "c:\temp\expected_version_centos"
    } 

    if ($global:isHyperV -eq $true) {
        if ($global:session -eq $null) {
             Write-Output "*** Restarting (2) the PowerShell session!" | out-file -Append /opt/microsoft/borg_progress.log
             get-pssession | remove-pssession
            $global:session=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $global:cred -authentication Basic -SessionOption $global:o
        }

        invoke-command -session $global:session -ScriptBlock ${function:callVersionIn} -ArgumentList $outFile,$m
    } else {
        $output_path="/HIPPEE/expected_version"

        $m | out-file -Append $output_path
    }
}

if (Get-Item -ErrorAction SilentlyContinue -Path /opt/microsoft/borg_progress.log ) {
    Remove-Item /opt/microsoft/borg_progress.log
}

Start-Transcript -path /HIPPEE/borg_install_log -force
#
#  Remove the old sentinel file and reset
#
Remove-Item -Force "/HIPPEE/expected_version"
write-output "System Initialization" | Out-File -Path "/HIPPEE/expected_version"
$failure_point="Setup"

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$c=hostname

$c | Out-File -FilePath /opt/microsoft/borg_progress.log
#
#  Start by cleaning out any existing downloads
#
$global:isHyperV=$true
nslookup cdmbuildsna01.redmond.corp.microsoft.com
if ($? -eq $false) {
    $global:isHyperV = $false
    phoneHome "It looks like we're in Azure"
} else {
    phoneHome "It looks like we're in Hyper-V"
}

phoneHome "******************************************************************"
phoneHome "*        BORG DRONE $hostName starting conversion..."
phoneHome "******************************************************************"

if ($ENV:PATH -ne "") {
    $ENV:PATH=$ENV:PATH + ":/sbin:/bin:/usr/sbin:/usr/bin:/opt/omi/bin:/usr/local:/usr/sbin:/bin"
} else {
    $ENV:PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/omi/bin:/usr/local:/usr/sbin:/bin"
}

$failure_point="chmod"
@(chmod 777 /opt/microsoft/borg_progress.log)
@(ls -laF /opt/microsoft/borg_progress.log)

$failure_point="cleaning old"
phoneHome "Starting copy file scipt"
set-location /HIPPEE
$kernFolder="/HIPPEE/latest_kernel"
If (Test-Path $kernFolder) {
    Remove-Item -Recurse -Force $kernFolder
}
new-item $kernFolder -type directory

$failure_point="Mounting"
if ($global:isHyperV -eq $true) {

    if ($pkg_mount_point -eq "Undefined") {
        $pkg_mount_point="/mnt/ostcnix"
        $pkg_mount_dir= $pkg_mount_point
    } else {
        $pkg_mount_dir=$pkg_mount_point
    }

    if ($pkg_mount_source -eq "Undefined") {
        $pkg_mount_source = "cdmbuildsna01.redmond.corp.microsoft.com:/OSTCNix/OSTCNix/Build_Drops/kernel_drops/latest"
    }

    phoneHome "Package mount point is $pkg_mount_point and Package mount dir is $pkg_mount_dir"
    phoneHome "Package source is $pkg_mount_source"

    if ((Test-Path $pkg_mount_point) -eq $false) {
        phoneHome "Creating the mount point"
        New-Item -ItemType Directory -Path $pkg_mount_point
        if ($? -eq $false) {
            $failure_point="CreateMount"
            ErrOut($failure_point)
        }
    }

    Write-Output "Checking for the mount directory..."
    if ((Test-Path $pkg_mount_dir/file_list) -eq $false) {
        write-output "mounting..."
        phoneHome "Target directory was not there.  Mounting"
        write-output "Command is mount $pkg_mount_source $pkg_mount_point"
        @(mount $pkg_mount_source $pkg_mount_point)
        if ($? -eq $false) {
            $failure_point="Mount"
            ErrOut($failure_point)
        }
    }

    if ((Test-Path $pkg_mount_dir) -eq 0) {
        phoneHome "Latest directory $pkg_mount_dir was not on mount point $pkg_mount_point!  No kernel to install!"
        phoneHome "Mount was from $pkg_mount_source"
        $failure_point-"NoSource"
        ErrOut($failure_point)
    }

    #
    #  Copy the files
    #
    phoneHome "Copying the kernel from the drop share"
    set-location /HIPPEE/latest_kernel

    copy-Item -Path $pkg_mount_dir/* -Destination ./
    if ($? -eq $false) {
        $failure_point="CopyKernelArtifacts"
        ErrOut($failure_point)
    }
} else {
    #
    #  If we can't mount the drop folder, maybe we can get the files from Azure
    #
    set-location $kernFolder

    phoneHome "Copying the kernel from Azure blob storage"
    $fileListURIBase = "https://" + $pkg_storageaccount + ".blob.core.windows.net/" + $pkg_container
    $fileListURI = $fileListURIBase + "/file_list"
    phoneHome "Downloading file list from URI $fileListURI"
    Invoke-WebRequest -Uri $fileListURI -OutFile file_list
    if ($? -eq $false) {
        $failure_point="GetFileListFromAzure"
        ErrOut($failure_point)
    }

    $files=Get-Content file_list

    foreach ($file in $files) {
        $fileListURIBase = "https://" + $pkg_storageaccount + ".blob.core.windows.net/" + $pkg_container
        $fileName=$fileListURIBase + "/" + $file
        Invoke-WebRequest -Uri $fileName -OutFile $file
        if ($? -eq $false) {
            $failure_point="WebDownloadFromAzure"
            ErrOut($failure_point)
        }
    }
}

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$linuxOs = $linuxInfo.ID
phoneHome "Operating system is $linuxOs"
$linuxVers = $linuxInfo.VERSION_ID
phoneHome "Operating system version is $linuxVers"

#
#  Figure out the kernel name
#
$failure_point="PrepareForInstall"
if (Test-Path /bin/rpm) {
    $kernel_name_cent=Get-ChildItem -Path /HIPPEE/latest_kernel/kernel-[0-9].* -Exclude "*.src*"
    $kernelNameCent = $kernel_name_cent.Name.split("-")[1]
    phoneHome "CentOS Kernel name is $kernelNameCent"

    #
    #  Figure out the kernel version
    #
    $kernelVersionCent=$kernelNameCent

    #
    #  For some reason, the file is -, but the kernel is _
    #
    $kernelVersionCent=($kernelVersionCent -replace "_","-")
    phoneHome "Expected Kernel version is $kernelVersionCent"
    $kernelVersionCent | Out-File -Path "/HIPPEE/expected_version"
    phoneVersionHome $kernelVersionCent
} else {
    $kernel_name_deb=Get-ChildItem -Path /HIPPEE/latest_kernel/linux-image-[0-9].* -Exclude "*-dbg_*"
    $kernelNameDeb = $kernel_name_deb.Name.split("image-")[1]
    phoneHome "Debian Kernel name is $kernelNameDeb"

    #
    #  Figure out the kernel version
    #
    $kernelVersionDeb=($kernelNameDeb -split "_")[0]

    #
    #  For some reason, the file is -, but the kernel is _
    #
    $kernelVersionDeb=($kernelVersionDeb -replace "_","-")
    phoneHome "Expected Kernel version is $kernelVersionDeb"
    $kernelVersionDeb | Out-File -Path "/HIPPEE/expected_version"
    phoneVersionHome $kernelVersionDeb
}

#
#  Do the right thing for the platform
#
set-location $kernFolder
$failure_point="Installing"
if (Test-Path /bin/rpm) {
    #
    #  rpm-based system
    #
    $kerneldevelName = Get-Childitem -Path /HIPPEE/latest_kernel/kernel-devel-[0-9].*.rpm
    phoneHome "Kernel Devel Package name is $kerneldevelName"

    $kernelPackageName = Get-ChildItem -Path /HIPPEE/latest_kernel/kernel-[0-9].*.rpm

    phoneHome "Making sure the firewall is configured"
    @(firewall-cmd --zone=public --add-port=443/tcp --permanent)
    if ($? -eq $false) {
        $failure_point="FirewallSetPort"
        ErrOut($failure_point)
    }

    #
    #  Don't care if we fail to stop it
    #
    @(systemctl stop firewalld)
    @(systemctl start firewalld)
    if ($? -eq $false) {
        $failure_point="FirewallStart"
        ErrOut($failure_point)
    }

    #
    #  Install the new kernel
    #
    phoneHome "Installing the rpm kernel devel package $kernelDevelName"
    @(rpm -ivh $kernelDevelName)
    if ($? -eq $false) {
        $failure_point="RPMInstallDevel"
        ErrOut($failure_point)
    }

    phoneHome "Installing the rpm kernel package $kernelPackageName"
    @(rpm -ivh $kernelPackageName)
    if ($? -eq $false) {
        $failure_point="RPMInstall"
        ErrOut($failure_point)
    }

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    $foo = @(/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg)
    if ($? -eq $false) {
        $failure_point="GrubSetBootSelection"
        ErrOut($failure_point)
    }

    $foo = @(/sbin/grub2-set-default 0)
    if ($? -eq $false) {
        $failure_point="GrubSetBootDefault"
        ErrOut($failure_point)
    }
} else {
    #
    #  Figure out the kernel name
    #
    $debKernName=(get-childitem linux-image-*.deb -exclude "-dgb_")[0].Name
    phoneHome "Kernel Package name is $debKernName"

    #
    #  Debian
    #
    $kernDevName=(get-childitem linux-image-*.deb -Exclude ".src.")[1].Name
    phoneHome "Kernel Devel Package name is $kernDevName"

    #
    #  In an ideal world, neither of these would be necessary. However,
    #  experience has shown that there are many more broken images that
    #  good, so let's at least try and get the system consistent before
    #  installing the kernel.
    #
    phoneHome "Trying to make sure the dpkg repository is in a conistent state"
    Remove-Item -Path /var/lib/dpkg/lock
    @(dpkg --configure -a)
    if ($? -eq $false) {
        ErrOut($failure_point)
        fail
    }

    @(apt-get install -f)
    if ($? -eq $false) {
        $failure_point="Install_F"
        ErrOut($failure_point)
    }

    @(apt autoremove -y)
    if ($? -eq $false) {
        $failure_point="SetAutoRemove"
        ErrOut($failure_point)
    }
    
    #
    #  Now make sure the system is current
    #
    phoneHome "Getting the system current"
    @(apt-get -y update)
    if ($? -eq $false) {
        $failure_point="AptGetUpdate"
        ErrOut($failure_point)
    }

    phoneHome "Installing the DEB kernel devel package"
    @(dpkg -i $kernDevName)
    if ($? -eq $false) {
        $failure_point="DpkgInstallDevel"
        ErrOut($failure_point)
    }

    phoneHome "Installing the DEB kernel package"
    @(dpkg -i $debKernName)
    if ($? -eq $false) {
        $failure_point="DpkgInstall"
        ErrOut($failure_point)
    }
    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    @(grub-mkconfig -o /boot/grub/grub.cfg)
    if ($? -eq $false) {
        $failure_point="GrubMkConfig"
        ErrOut($failure_point)
    }

    @(grub-set-default 0)
    if ($? -eq $false) {
        $failure_point="GrubSetDefault"
        ErrOut($failure_point)
    }
}

#
#  Copy the post-reboot script to RunOnce
#
copy-Item -Path "/HIPPEE/Framework-Scripts/report_kernel_version.ps1" -Destination "/HIPPEE/runonce.d"

phoneHome "Rebooting now..."

if ($global:isHyperV -eq $true) {
    remove-pssession $global:session
}

Stop-Transcript

# 
#  This will reboot the system
#
shutdown -r

exit 0