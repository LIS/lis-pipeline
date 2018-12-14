# How to configure a YUM http repository

Tested on CentOS Linux 7.

## Requirements
CentOS Linux 7 where the YUM repository will be created and configured (SERVER).

CentOS Linux 7 where YUM will be configured to install packages from the previously configured repository (CLIENT).

## On the repository machine

Make a directory containing all rpm files you want to share, in this example it will be /var/www/html/repo .
```bash
sudo yum install -y createrepo httpd
sudo createrepo /var/www/html/repo
# Now you can access your packages from http://<YOUR-SERVER-IP>/repo/ .
```
## On the client
```bash
sudo vi /etc/yum.repos.d/localrepo.repo
```
Add the following content:
```bash
[localrepo]
name=CentOS Repository
baseurl=http://<YOUR-SERVER-IP>/repo/
gpgcheck=0
enabled=1
```
You can now verify if your repository is in the YUM repo list:
```bash
yum repolist
```
