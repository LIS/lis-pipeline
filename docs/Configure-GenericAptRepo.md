# How to configure a generic aptitude repository

Tested on Ubuntu Xenial 16.04

## Requirements
Ubuntu Xenial 16.04 where the aptitude repository will be created and configured.

Ubuntu Xenial 16.04 where aptitude will be configured to install packages from the previously configured repository.

## On the repository machine:

Create a directory containing all debian files you want to share, in this example it will be ~/deb
```bash
sudo apt-get install apache2 apt-transport-https dpkg-dev
sudo cp -r ~/deb /var/www/html
cd /var/www/html/deb
# This will be required to be run every time you add/remove a package.
dpkg-scanpackages -m . | sudo gzip -c > Packages.gz
```

## On the client
```bash
# apt_repo_server_hostname is the Ubuntu machine's IP which has the apt repository configured.
sudo sh -c  'echo "deb [trusted=yes] http://<apt_repo_server_hostname>/deb ./" \
     >> /etc/apt/sources.list'
sudo apt-get update
```
You can now search for the packages
```bash
apt-cache search <package-name>
```
