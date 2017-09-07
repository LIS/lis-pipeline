
These scripts automate the packaging of the LIS daemons from source code.

Tested on: Ubuntu 14.04, Ubuntu 16.04 and CentOS 7

Tested with Linux kernel 4.12.8

## Man
~~~
-u  URL to a linux kernel source
-r  Linux kernel git repo
-b  Branch for the repo
-l  Path to a local kernel folder
-v  Target OS release version. Ex: 14, 16 ( mandatory for Ubuntu )
~~~
## Steps to generate packages
~~~
Clone this repo.
Run ./build-lis-daemons-rpm(deb).sh as root with the desired params.
~~~
## Example
~~~
# Get kernel sources from URL and build debs for Ubuntu 16 (systemd)
./build-lis-daemons-deb.sh -u https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.12.9.tar.xz -v 16 
# Get kernel sources from repo and build rpms from CentOS, RHEL (systemd).
./build-lis-daemons-rpm.sh -r https://github.com/torvalds/linux.git -b master 
# Get kernel sources from a local folder and build rpms from CentOS, RHEL (systemd).
./build-lis-daemons-rpm.sh -l /home/test/linux-next 
~~~
## Notes
~~~
When you install the LIS package make sure you don't have installed any package that contains the LIS daemons (ex: linux-cloud-tools-virtual). If you do, you must remove it before.
After the script is done the packages will be in the working_directory/hyperv-debs(rpms).
You can't create debs for Ubuntu 15 or higher on a Ubuntu 14.04 machine.
The rpms must be installed as : sudo rpm -i /path/to/rpms/*.rpm     ( dependency problems ).
On CentOS, a restart is needed after daemons install. 
~~~
