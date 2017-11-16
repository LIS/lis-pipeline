Name:              perf
License:           GPLv2+
Summary:           Linux perf tool
BuildArch:         x86_64
Release:           1
Version:           1
Source0:           tools
BuildRoot:         %{_tmppath}/%{name}-%{version}-build
Requires:          kernel >= 3.10.0-123
BuildRequires:     kernel-headers

%description
Perf tool for the linux kernel.

%prep
%setup -Tc
sudo cp -r %{SOURCE0} .

%install
cd ./tools/perf
make DESTDIR=%{buildroot}%{_usr} install install-doc
mv %{buildroot}%{_usr}/etc %{buildroot}

%files
%defattr(-,root,root)
%{_bindir}/perf
%dir %{_libdir}/traceevent/plugins
%{_libdir}/traceevent/plugins/*
%dir %{_libexecdir}/perf-core
%{_libexecdir}/perf-core/*
%{_mandir}/man[1-8]/perf*
%{_sysconfdir}/bash_completion.d/perf
%{_bindir}/trace
%{_usr}/%{_lib}/libperf-gtk.so
%{_usr}/share/doc/perf-tip/tips.txt