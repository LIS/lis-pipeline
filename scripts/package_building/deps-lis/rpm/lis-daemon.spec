
%global hv_kvp_daemon hypervkvpd
%global hv_vss_daemon hypervvssd
%global hv_fcopy_daemon hypervfcopyd

# nodebuginfo
# norootforbuild


%define releasetag public
%define release %(date +%Y%m%d)
%define _unpackaged_files_terminate_build 0

Name:			hyperv-daemons
License:		GPLv2+
Summary:		Microsoft hyper-v daemons
Version:		1
Release:		0.29%{?snapver}%{?dist}
Source0:		hv_kvp_daemon.c	
Source1:		hypervkvpd.service	
Source2:		hypervkvp.rules	
Source3:		hv_get_dhcp_info.sh	
Source4:		hv_get_dns_info.sh	
Source5:		hv_set_ifconfig.sh	
Source6:		hv_vss_daemon.c	
Source7:		hypervvss.rules	
Source8:		hypervvssd.service	
Source9:		hv_fcopy_daemon.c	
Source10:		hypervfcopy.rules	
Source11:		hypervfcopyd.service
Source12:		Makefile	
Source13:		Build
BuildRoot:		%{_tmppath}/%{name}-%{version}-build
Requires:		kernel >= 3.10.0-123
BuildRequires:		systemd, kernel-headers
Requires(post):		systemd
Requires(preun):	systemd
Requires(postun):	systemd


%description
Suite of daemons that are needed when Linux guest is running on Windows host with HyperV. 

%prep
%setup -Tc
cp -pvL %{SOURCE0} hv_kvp_daemon.c
cp -pvL %{SOURCE3} hv_get_dhcp_info.sh
cp -pvL %{SOURCE4} hv_get_dns_info.sh
cp -pvL %{SOURCE5} hv_set_ifconfig.sh
cp -pvL %{SOURCE1} %{hv_kvp_daemon}.service

cp -pvL %{SOURCE6} hv_vss_daemon.c
cp -pvL %{SOURCE8} %{hv_vss_daemon}.service

cp -pvL %{SOURCE9} hv_fcopy_daemon.c
cp -pvL %{SOURCE10} %{hv_fcopy_daemon}.service

cp -pvL %{SOURCE12} Makefile
if [ ! -e "%{SOURCE13}" ]; then
  touch %{SOURCE13}
fi
cp -pvL %{SOURCE13} Build
%build
make clean
make

%install

mkdir -p %{buildroot}%{_sbindir}
install -p -m 0755 hv_kvp_daemon %{buildroot}%{_sbindir}/%{hv_kvp_daemon}
install -p -m 0755 hv_vss_daemon %{buildroot}%{_sbindir}/%{hv_vss_daemon}
install -p -m 0755 hv_fcopy_daemon %{buildroot}%{_sbindir}/%{hv_fcopy_daemon}

# Systemd unit file
mkdir -p %{buildroot}%{_unitdir}
install -p -m 0644 %{SOURCE1} %{buildroot}%{_unitdir}
install -p -m 0644 %{SOURCE8} %{buildroot}%{_unitdir}
install -p -m 0644 %{SOURCE11} %{buildroot}%{_unitdir}

# Udev rules
mkdir -p %{buildroot}%{_udevrulesdir}
install -p -m 0644 %{SOURCE2} %{buildroot}%{_udevrulesdir}/%{udev_prefix}-70-hv_kvp.rules
install -p -m 0644 %{SOURCE7} %{buildroot}%{_udevrulesdir}/%{udev_prefix}-70-hv_vss.rules
install -p -m 0644 %{SOURCE10} %{buildroot}%{_udevrulesdir}/%{udev_prefix}-70-hv_fcopy.rules

# Shell scripts for the KVP daemon
mkdir -p %{buildroot}%{_libexecdir}/%{hv_kvp_daemon}
install -p -m 0755 %{SOURCE3} %{buildroot}%{_libexecdir}/%{hv_kvp_daemon}/hv_get_dhcp_info
install -p -m 0755 %{SOURCE4} %{buildroot}%{_libexecdir}/%{hv_kvp_daemon}/hv_get_dns_info
install -p -m 0755 %{SOURCE5} %{buildroot}%{_libexecdir}/%{hv_kvp_daemon}/hv_set_ifconfig

# Directory for pool files
mkdir -p %{buildroot}%{_sharedstatedir}/hyperv

%preun
if [ $1 -eq 0 ]; then # package is being erased, not upgraded
    echo "Removing Package.."
    echo "Stopping KVP Daemon...."
    systemctl stop hypervkvpd
    echo "Stopping FCOPY Daemon...."
    systemctl stop hypervfcopyd
    echo "Stopping VSS Daemon...."
    systemctl stop hypervvssd
    rm -rf %{_sharedstatedir}/hyperv || :
fi

%post
if [ $1 > 1 ] ; then
    # Upgrade
    systemctl --no-reload disable hypervkvpd.service  >/dev/null 2>&1 || :
    systemctl --no-reload disable hypervvssd.service  >/dev/null 2>&1 || :
    systemctl --no-reload disable hypervfcopyd.service  >/dev/null 2>&1 || :
fi

%postun 
%systemd_postun hypervkvpd.service
%systemd_postun hypervvssd.service
%systemd_postun hypervfcopyd.service

%files
%{_sbindir}/%{hv_kvp_daemon}
%{_unitdir}/hypervkvpd.service
%{_udevrulesdir}/%{udev_prefix}-70-hv_kvp.rules
%dir %{_libexecdir}/%{hv_kvp_daemon}
%{_libexecdir}/%{hv_kvp_daemon}/*
%dir %{_sharedstatedir}/hyperv
%{_sbindir}/%{hv_vss_daemon}
%{_unitdir}/hypervvssd.service
%{_udevrulesdir}/%{udev_prefix}-70-hv_vss.rules
%{_sbindir}/%{hv_fcopy_daemon}
%{_unitdir}/hypervfcopyd.service
%{_udevrulesdir}/%{udev_prefix}-70-hv_fcopy.rules
