#!/usr/bin/env bash
# Builds a private, patched strongSwan into /opt/cygnet and installs the cygnet command and
# the Cygnet app, on Ubuntu/Debian or Manjaro/Arch. Run it as your normal user; it uses sudo
# where needed.
#
#   ./install.sh            install everything
#   ./install.sh --no-gui   leave out the app (and remove it, if an earlier run installed it)
#
# It is separate from any distro strongSwan package, so updates can't overwrite it. Run this
# again if cygnet stops starting after a system update (e.g. a new OpenSSL). Your connections
# are kept.
#
# A vpn.conf next to this script, from an earlier version, is imported as a connection.
set -eu

VERSION=6.1.0
SHA256=fe6c97481298767213cfc2e9a1da29fdd8018d481ff4cb9cf0283099654f20d4
PREFIX=/opt/cygnet
SERVICE=cygnet.service
APP_ID=io.github.Khalid_AlHajri.Cygnet

GUI_FILES=(
    /usr/local/bin/cygnet-gui
    /usr/local/share/applications/$APP_ID.desktop
    /usr/local/share/icons/hicolor/scalable/apps/$APP_ID.svg
    /usr/share/polkit-1/actions/$APP_ID.policy
    /etc/polkit-1/rules.d/50-cygnet.rules
)

gui=1
for arg; do
    case $arg in
    --no-gui) gui= ;;
    *)
        echo "usage: ./install.sh [--no-gui]" >&2
        exit 2
        ;;
    esac
done

[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not with sudo." >&2; exit 1; }
HERE=$(dirname "$(readlink -f "$0")")

echo "==> Installing dependencies"
if command -v pacman >/dev/null; then
    sudo pacman -S --needed base-devel openssl systemd curl ${gui:+gtk4 libadwaita python-gobject}
elif command -v apt-get >/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y build-essential pkg-config libssl-dev libsystemd-dev curl bzip2 \
        ${gui:+python3-gi gir1.2-gtk-4.0 gir1.2-adw-1}
else
    echo "Unsupported distro: install a C toolchain and the OpenSSL and systemd headers," >&2
    echo "plus GTK 4, libadwaita and PyGObject for the app, then remove this check." >&2
    exit 1
fi

BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

echo "==> Downloading strongSwan $VERSION"
curl -fsSL -o "$BUILD/src.tar.bz2" "https://download.strongswan.org/strongswan-$VERSION.tar.bz2"
echo "$SHA256  $BUILD/src.tar.bz2" | sha256sum -c --quiet
mkdir "$BUILD/src"
tar -xjf "$BUILD/src.tar.bz2" -C "$BUILD/src" --strip-components=1
cd "$BUILD/src"

echo "==> Applying patches"
for patch in "$HERE"/patches/*.patch; do
    patch -p1 -s <"$patch"
done

echo "==> Building (this takes a few minutes)"
./configure --prefix="$PREFIX" --sysconfdir="$PREFIX/etc" --with-piddir=/run/cygnet \
    --with-systemdsystemunitdir="$PREFIX/lib/systemd/system" --disable-static \
    --enable-systemd --enable-eap-identity --enable-eap-mschapv2 --enable-eap-gtc --enable-md4 \
    >"$BUILD/configure.log" 2>&1 || { tail -n 30 "$BUILD/configure.log" >&2; exit 1; }
make -j"$(nproc)" >"$BUILD/make.log" 2>&1 || { tail -n 30 "$BUILD/make.log" >&2; exit 1; }

echo "==> Installing to $PREFIX"
sudo systemctl stop "$SERVICE" 2>/dev/null || true
sudo make install >"$BUILD/install.log" 2>&1 || { tail -n 30 "$BUILD/install.log" >&2; exit 1; }

sudo install -m 644 "$HERE/strongswan-fortigate.conf" "$PREFIX/etc/strongswan.d/fortigate.conf"
sudo install -d -m 755 "$PREFIX/libexec" "$PREFIX/etc/connections"
sudo install -m 755 "$HERE/otp-helper" "$HERE/dns-hook" "$PREFIX/libexec/"
sudo install -m 644 "$HERE/$SERVICE" "/etc/systemd/system/$SERVICE"
sudo install -m 755 "$HERE/cygnet" /usr/local/bin/cygnet

if [[ -n $gui ]]; then
    echo "==> Installing the Cygnet app"
    sudo install -D -m 755 "$HERE/gui/cygnet-gui" "${GUI_FILES[0]}"
    sudo install -D -m 644 "$HERE/gui/data/$APP_ID.desktop" "${GUI_FILES[1]}"
    sudo install -D -m 644 "$HERE/gui/data/$APP_ID.svg" "${GUI_FILES[2]}"
    sudo install -D -m 644 "$HERE/polkit/$APP_ID.policy" "${GUI_FILES[3]}"
    sudo install -D -m 644 "$HERE/polkit/50-cygnet.rules" "${GUI_FILES[4]}"
    sudo gtk-update-icon-cache -qtf /usr/local/share/icons/hicolor 2>/dev/null || true
else
    sudo rm -f "${GUI_FILES[@]}"
fi
sudo systemctl daemon-reload

if [[ -r $HERE/vpn.conf ]] && [[ -z $(ls -A "$PREFIX/etc/connections") ]]; then
    sudo /usr/local/bin/cygnet import "$HERE/vpn.conf" || true
fi

echo
if [[ -z $(ls -A "$PREFIX/etc/connections") ]]; then
    echo "Installed. Add a connection${gui:+ in the Cygnet app, or} with: cygnet add"
elif [[ -n $gui ]]; then
    echo "Installed. Open Cygnet from your apps, or connect with: cygnet"
else
    echo "Installed. Connect with: cygnet"
fi
