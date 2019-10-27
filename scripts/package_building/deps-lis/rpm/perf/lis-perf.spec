Name:              perf
License:           GPLv2+
Summary:           Linux perf tool
BuildArch:         x86_64
Release:           1
Version:           1
Source0:           tools
Source1:           include
Source2:           scripts
BuildRoot:         %{_tmppath}/%{name}-%{version}-build
Requires:          kernel >= 3.10.0-123
BuildRequires:     kernel-headers

%description
Perf tool for the linux kernel.

%prep
%setup -Tc
sudo cp -r %{SOURCE0} .
sudo cp -r %{SOURCE1} .
sudo cp -r %{SOURCE2} .

%install
cd ./tools/perf
make DESTDIR=%{buildroot}%{_usr} install install-doc
mv %{buildroot}%{_usr}/etc %{buildroot}
mkdir -p %{buildroot}%{_usr}/lib/
pushd %{buildroot}
find ./usr/lib -type f | sed 's\^.\\' > %{_topdir}/generated-files
popd

%files -f %{_topdir}/generated-files
%defattr(-,root,root)
%{_bindir}/perf
%dir %{_libdir}/traceevent/plugins
%{_libdir}/traceevent/plugins/*
%dir %{_libexecdir}/perf-core
%{_libexecdir}/perf-core/*
%{_mandir}/man[1-8]/perf*
%{_sysconfdir}/bash_completion.d/perf
%{_bindir}/trace
%{_usr}/share/*
%{_usr}/lib64/libperf-jvmti.so
