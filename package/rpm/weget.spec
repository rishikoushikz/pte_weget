Name:           weget
Version:        0.1
Release:        1%{?dist}
Summary:        Modern macOS-style interactive desktop widgets for Linux
License:        MIT
URL:            https://github.com/weget/weget
BuildArch:      x86_64

AutoReqProv:    no

%description
Weget provides modular, pixel-perfect Cairo desktop widgets (Clock, Calendar,
Weather, Storage, Media, Rings, Quotes, Network) powered by an inbuilt
Conky runtime engine with zero manual dependencies.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/lib/weget/engine/bin
mkdir -p %{buildroot}/usr/lib/weget/engine/lib
mkdir -p %{buildroot}/usr/share/weget
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps

install -m 755 %{_sourcedir}/usr/bin/weget %{buildroot}/usr/bin/weget
install -m 755 %{_sourcedir}/usr/lib/weget/engine/bin/conky %{buildroot}/usr/lib/weget/engine/bin/conky
install -m 644 %{_sourcedir}/usr/lib/weget/engine/lib/*.so %{buildroot}/usr/lib/weget/engine/lib/
cp -a %{_sourcedir}/usr/share/weget/* %{buildroot}/usr/share/weget/
install -m 644 %{_sourcedir}/usr/share/applications/weget.desktop %{buildroot}/usr/share/applications/weget.desktop
install -m 644 %{_sourcedir}/usr/share/icons/hicolor/256x256/apps/weget.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/weget.png

%files
/usr/bin/weget
/usr/lib/weget
/usr/share/weget
/usr/share/applications/weget.desktop
/usr/share/icons/hicolor/256x256/apps/weget.png

%changelog
* Wed Oct 15 2026 Weget Team <support@weget.org> - 0.1-1
- Release 0.1 with bundled Conky engine and zero freeze architecture.
