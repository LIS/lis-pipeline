
Name:              hyperv-tools
License:           GPLv2+
Summary:           Microsoft hyper-v tools
BuildArch:         noarch
Release:           0.29%{?snapver}%{?dist}
Version:           1
Source0:           lsvmbus
BuildRoot:         %{_tmppath}/%{name}-%{version}-build
Requires:          kernel >= 3.10.0-123
BuildRequires:     kernel-headers

%description
lsvmbus

%prep
%setup -Tc
cp -pvL %{SOURCE0} lsvmbus

%install
mkdir -p %{buildroot}%{_sbindir}
install -p -m 0755 lsvmbus %{buildroot}%{_sbindir}

%files
%{_sbindir}/lsvmbus
