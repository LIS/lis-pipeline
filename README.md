# Jenkins Blue Ocean pipeline for kernel testing

## Jenkins

### Jenkins Linux Slaves
TBD

### Jenkins Windows Slave

#### Installation
It is mandatory to run the Jenkins slave as a service on Windows and have the installed Java version as the one from the Jenkins master.
Otherwise the Windows slave connection to the master will show arbitrary disconnects that will lead to the whole pipeline failing.

#### Windows packages/folders required:
  * Hyper-V module needs to be installed and enabled
  * A Hyper-V switch named "External" needs to be created so that VMs have Internet access
  * A folder C:\workspace needs to be created, with full access for the LocalSystem user
  * A folder C:\bin needs to be created, with full access for the LocalSystem user

#### Windows external tools required (need to be added to the system path):
  * java.exe - downloadable from https://java.com/en/download/
  * git.exe - downloadable from https://git-scm.com/download/win
  * ssh.exe - already in the <git_installation_folder>/usr/bin
  * scp.exe - already in the <git_installation_folder>/usr/bin
  * icaserial.exe - source code downloadable from https://github.com/LIS/lis-test/tree/master/WS2008R2/lisa/Tools/icaserial
  * qemu-img.exe and the required .dlls - downloadable from https://cloudbase.it/downloads/qemu-img-win-x64-2_3_0.zip
