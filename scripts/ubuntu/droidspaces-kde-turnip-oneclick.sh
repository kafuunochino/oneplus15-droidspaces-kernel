#!/usr/bin/env bash
# OnePlus 15 / Adreno 840 native Turnip and KDE Plasma X11 setup.
set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
	echo "This installer must run as root (use sudo or enter a root shell)." >&2
	exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 24.04 ]]; then
	echo "This installer is only for Ubuntu 24.04." >&2
	exit 1
fi
case "$(uname -m)" in
	aarch64|arm64) ;;
	*)
		echo "This installer is only for the aarch64/arm64 container." >&2
		exit 1
		;;
esac

desktop_user="${SUDO_USER:-${XFCE_USER:-}}"
if [[ -z "$desktop_user" || "$desktop_user" == root ]]; then
	desktop_user="$(
		getent passwd |
			awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1; exit }'
	)"
fi
desktop_user="${desktop_user:-root}"
if [[ ! "$desktop_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] ||
	! id "$desktop_user" >/dev/null 2>&1; then
	echo "Could not select a valid desktop user: $desktop_user" >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y software-properties-common ca-certificates curl
add-apt-repository -y universe
apt-get update
apt-get install -y --no-install-recommends \
	kde-plasma-desktop plasma-workspace kwin-x11 systemsettings \
	breeze breeze-cursor-theme breeze-icon-theme breeze-gtk-theme \
	papirus-icon-theme konsole dolphin kate ark \
	dbus-x11 x11-xserver-utils xdg-utils xdg-user-dirs \
	fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji \
	locales language-pack-zh-hans \
	fcitx5 fcitx5-chinese-addons fcitx5-config-qt im-config \
	pulseaudio-utils mesa-utils glmark2-x11 vulkan-tools \
	gdebi curl ca-certificates tar xz-utils

locale-gen en_US.UTF-8 zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8

mesa_version=26.2.0-devel-20260709
mesa_file="mesa-for-android-container_${mesa_version}_ubuntu_noble_arm64.tar.gz"
mesa_url="https://github.com/lfdevs/mesa-for-android-container/releases/download/mesa-${mesa_version}/${mesa_file}"
mesa_sha256=89adc0d7b7eaa26e619cd6c41114894c152fa1680d0ff1969947e94e151f660f
mesa_work="$(mktemp -d /tmp/droidspaces-mesa.XXXXXXXX)"
trap 'rm -rf -- "$mesa_work"' EXIT

curl --fail --location --proto '=https' --tlsv1.2 \
	--output "$mesa_work/$mesa_file" "$mesa_url"
printf '%s  %s\n' "$mesa_sha256" "$mesa_work/$mesa_file" |
	sha256sum --check --strict

if tar -tzf "$mesa_work/$mesa_file" |
	grep -Eq '(^/|(^|/)\.\.(/|$))'; then
	echo "Unsafe path found in the Mesa archive; refusing to extract." >&2
	exit 1
fi
install -d -m 0755 /var/lib/droidspaces-gpu
tar -tzf "$mesa_work/$mesa_file" \
	>"/var/lib/droidspaces-gpu/${mesa_file}.contents"
tar -xzf "$mesa_work/$mesa_file" -C /
ldconfig
printf '%s\n' "$mesa_version" >/var/lib/droidspaces-gpu/mesa-version

cat >/etc/profile.d/99-droidspaces-turnip.sh <<'PROFILE'
# Native Adreno KGSL/Turnip path. Droidspaces VirGL must be disabled.
unset GALLIUM_DRIVER
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
export TU_DEBUG=noconform
export XDG_SESSION_TYPE=x11
export QT_QPA_PLATFORM=xcb
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
PROFILE
chmod 0644 /etc/profile.d/99-droidspaces-turnip.sh

printf 'DESKTOP_USER=%q\n' "$desktop_user" >/etc/default/droidspaces-kde
chmod 0644 /etc/default/droidspaces-kde

cat >/usr/local/bin/droidspaces-kde-start <<'LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

source /etc/default/droidspaces-kde
if [[ -r /run/droidspaces.env ]]; then
	source /run/droidspaces.env
fi
export DISPLAY="${DISPLAY:-:5}"
unset GALLIUM_DRIVER
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
export TU_DEBUG=noconform
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=KDE
export XDG_CURRENT_DESKTOP=KDE
export QT_QPA_PLATFORM=xcb
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx

desktop_uid="$(id -u "$DESKTOP_USER")"
desktop_gid="$(id -g "$DESKTOP_USER")"
install -d -m 0700 -o "$desktop_uid" -g "$desktop_gid" \
	"/run/user/$desktop_uid"
export XDG_RUNTIME_DIR="/run/user/$desktop_uid"

if [[ "$DESKTOP_USER" == root ]]; then
	export HOME=/root USER=root LOGNAME=root
	exec dbus-run-session -- startplasma-x11
fi

whitelist=DISPLAY,PULSE_SERVER,MESA_LOADER_DRIVER_OVERRIDE,TU_DEBUG
whitelist+=,XDG_RUNTIME_DIR,XDG_SESSION_TYPE,XDG_SESSION_DESKTOP
whitelist+=,XDG_CURRENT_DESKTOP,QT_QPA_PLATFORM
whitelist+=,GTK_IM_MODULE,QT_IM_MODULE,XMODIFIERS
exec su -l -w "$whitelist" "$DESKTOP_USER" \
	-c 'exec dbus-run-session -- startplasma-x11'
LAUNCHER
chmod 0755 /usr/local/bin/droidspaces-kde-start

cat >/etc/systemd/system/droidspaces-kde.service <<'SERVICE'
[Unit]
Description=KDE Plasma X11 for Droidspaces
After=graphical.target

[Service]
Type=simple
ExecCondition=/bin/sh -c "grep -q 'enable_termux_x11=1' /run/droidspaces/container.config"
ExecCondition=/bin/sh -c "test -S /tmp/.X11-unix/X5"
ExecStart=/usr/local/bin/droidspaces-kde-start
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
SERVICE

if [[ "$desktop_user" != root ]] &&
	getent group droidspaces-gpu >/dev/null; then
	usermod -aG droidspaces-gpu "$desktop_user"
fi

systemctl disable xfce-autostart.service 2>/dev/null || true
systemctl disable de-autostart.service 2>/dev/null || true
systemctl daemon-reload
systemctl enable droidspaces-kde.service
systemctl set-default graphical.target

cat <<EOF

Installation completed.
Desktop user: $desktop_user
Mesa: $mesa_version (native KGSL/Turnip)

Now STOP the container and configure Droidspaces:
  Configure Termux:X11: ON
  GPU Access: ON
  Configure VirGL 3D Acceleration: OFF
  Configure PulseAudio: ON

Start the container again and open Termux:X11.
After the KDE desktop appears, test:
  glxinfo -B
  glmark2
  vulkaninfo --summary

The renderer must not say llvmpipe or virpipe.
EOF
