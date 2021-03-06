#!/usr/bin/env bash

# Configure Z01 Ubuntu
set -euo pipefail
IFS='
'

# The value of this parameter is expanded like PS1 and the expanded value is the
# prompt printed before the command line is echoed when the -x option is set
# (see The Set Builtin). The first character of the expanded value is replicated
# multiple times, as necessary, to indicate multiple levels of indirection.
# \D{%F %T} prints date like this : 2019-12-31 23:59:59
PS4='-\D{%F %T} '

# Print commands and their arguments as they are executed.
set -x

# Log stdout & stderr
exec > >(tee -i /tmp/install_ubuntu.log) 2>&1

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# Skip dialogs during apt-get install commands
export DEBIAN_FRONTEND=noninteractive # DEBIAN_PRIORITY=critical

export LC_ALL=C LANG=C
export SHELL=/bin/bash

disk=$(lsblk -o tran,kname,hotplug,type,fstype -pr |
	grep '0 disk' |
	cut -d' ' -f2 |
	sort |
	head -n1)

systemctl stop unattended-upgrades.service

apt-get --no-install-recommends update
apt-get --no-install-recommends -y upgrade
apt-get -y autoremove --purge

apt-get --no-install-recommends -y install curl

# Remove outdated kernels
# old_kernels=$(ls -1 /boot/config-* | sed '$d' | xargs -n1 basename | cut -d- -f2,3)

# for old_kernel in $old_kernels; do
# 	dpkg -P $(dpkg-query -f '${binary:Package}\n' -W *"$old_kernel"*)
# done

apt-get -yf install

# Configure Terminal

# Makes bash case-insensitive
cat <<EOF >> /etc/inputrc
set completion-ignore-case
set show-all-if-ambiguous On
set show-all-if-unmodified On
EOF

# Enhance Linux prompt
cat <<EOF > /etc/issue
Kernel build: \v
Kernel package: \r
Date: \d \t
IP address: \4
Terminal: \l@\n.\O

EOF

# Enable Bash completion
apt-get --no-install-recommends -y install bash-completion

cat <<EOF >> /etc/bash.bashrc
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF

# Set-up all users
for dir in $(ls -1d /root /home/* 2>/dev/null ||:)
do
	# Hide login informations
	touch "$dir/.hushlogin"

	# Add convenient aliases & behaviors
	cat <<-'EOF'>> "$dir/.bashrc"
	export LS_OPTIONS="--color=auto"
	eval "`dircolors`"

	alias df="df --si"
	alias du="du --si"
	alias free="free -h --si"
	alias l="ls $LS_OPTIONS -al --si --group-directories-first"
	alias less="less -i"
	alias nano="nano -clDOST4"
	alias pstree="pstree -palU"

	HISTCONTROL=ignoreboth
	HISTFILESIZE=
	HISTSIZE=
	HISTTIMEFORMAT="%F %T "
	EOF

	# Fix rights
	usr=$(echo "$dir" | rev | cut -d/ -f1 | rev)
	chown -R "$usr:$usr" "$dir" ||:
done

# Install OpenSSH

ssh_port=512

# Install dependencies
apt-get --no-install-recommends -y install ssh

cat <<EOF >> /etc/ssh/sshd_config
Port $ssh_port
PasswordAuthentication no
AllowUsers root
EOF

# Install firewall

apt-get --no-install-recommends -y install ufw

ufw logging off
ufw allow in "$ssh_port"/tcp
ufw allow in 27960:27969/tcp
ufw allow in 27960:27969/udp
ufw --force enable

# Install Grub

sed -i -e 's/message=/message_null=/g' /etc/grub.d/10_linux

cat <<EOF >> /etc/default/grub
GRUB_TIMEOUT=0
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_TERMINAL=console
GRUB_DISTRIBUTOR=``
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_SUBMENU=y
EOF

update-grub
grub-install "$disk"


# Java pckages
javapkgs="
openjdk-8-jre
openjdk-8-jdk
"

apt-get --no-install-recommends -y install $javapkgs

# Flutter additional packages
flutterpkgs="
clang
cmake
ninja-build
pkg-config
libgtk-3-dev
"

apt-get --no-install-recommends -y install $flutterpkgs

# Install Chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
dpkg -i --force-depends google-chrome-stable_current_amd64.deb
rm google-chrome-stable_current_amd64.deb

# Prepare env for flutter
cat <<EOF >> /etc/profile
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64/
export ANDROID=\$HOME/Android
export PATH=\$ANDROID/cmdline-tools/tools:\$PATH
export PATH=\$ANDROID/cmdline-tools/tools/bin:\$PATH
export PATH=\$ANDROID/platform-tools:\$PATH
export ANDROID_SDK=\$HOME/\$ANDROID
export PATH=\$ANDROID_SDK:\$PATH
export FLUTTER=\$HOME/flutter
export PATH=\$FLUTTER/bin:\$PATH
EOF

export ANDROID=/home/student/Android
export PATH=$ANDROID/cmdline-tools/tools:$PATH
export PATH=$ANDROID/cmdline-tools/tools/bin:$PATH
export PATH=$ANDROID/platform-tools:$PATH
export ANDROID_SDK=/home/student/Android
export PATH=$ANDROID_SDK:$PATH
export FLUTTER=/home/student/flutter
export PATH=$FLUTTER/bin:$PATH

# Download Android tools
sudo -iu student wget https://dl.google.com/android/repository/commandlinetools-linux-7302050_latest.zip --output-document /home/student/android.zip
sudo -iu student mkdir -p /home/student/Android/cmdline-tools
sudo -iu student unzip /home/student/android.zip -d /home/student/Android/cmdline-tools
sudo -iu student mv /home/student/Android/cmdline-tools/cmdline-tools /home/student/Android/cmdline-tools/tools
rm /home/student/android.zip

# Download Flutter tar
sudo -iu student wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_2.2.2-stable.tar.xz --output-document /home/student/flutter.tar
# Extract Flutter
sudo -iu student tar -C /home/student/ -xf /home/student/flutter.tar
rm /home/student/flutter.tar

set +e
sudo -iu student yes | sdkmanager --sdk_root=${ANDROID} tools
set -e
sudo -iu student sdkmanager "system-images;android-29;google_apis;x86_64"
sudo -iu student sdkmanager "platforms;android-29"
sudo -iu student sdkmanager "platform-tools"
sudo -iu student sdkmanager "patcher;v4"
sudo -iu student sdkmanager "emulator"
sudo -iu student sdkmanager "build-tools;29.0.2"
set +e
sudo -iu student yes | sdkmanager --licenses
set -e
sudo -iu student flutter config --android-sdk /home/student/Android
sudo -iu student flutter doctor
sudo -iu student avdmanager -s create avd -n stand -k "system-images;android-29;google_apis;x86_64" -d 5

# Install Go

wget https://dl.google.com/go/go1.16.3.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.16.3.linux-amd64.tar.gz
rm go1.16.3.linux-amd64.tar.gz
# shellcheck disable=2016
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

# Set-up all users
for dir in $(ls -1d /root /home/* 2>/dev/null ||:)
do
	# Add convenient aliases & behaviors
	cat <<-'EOF'>> "$dir/.bashrc"
	GOPATH=$HOME/go
	PATH=$PATH:$GOPATH/bin
	alias gobuild='CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w"'
	EOF
	# shellcheck disable=2016
	echo 'GOPATH=$HOME/go' >> "$dir/.profile"

	# Fix rights
	usr=$(echo "$dir" | rev | cut -d/ -f1 | rev)
	chown -R "$usr:$usr" "$dir" ||:
done

# Install Node.js

curl -sL https://deb.nodesource.com/setup_14.x | bash -
apt-get --no-install-recommends -y install nodejs

# Install FX: command-line JSON processing tool (https://github.com/antonmedv/fx)

npm install -g fx

# Install Sublime Text & Sublime Merge

wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | apt-key add -
apt-get --no-install-recommends install -y apt-transport-https

cat <<EOF > /etc/apt/sources.list.d/sublime-text.list
deb https://download.sublimetext.com/ apt/stable/
EOF

apt-get --no-install-recommends update
apt-get --no-install-recommends install -y sublime-text sublime-merge libgtk2.0-0

# Install Visual Studio Code

wget 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64' --output-document vscode.deb
dpkg -i vscode.deb
rm vscode.deb

# Install VSCodium

wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor | dd of=/etc/apt/trusted.gpg.d/vscodium-archive-keyring.gpg
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/vscodium-archive-keyring.gpg] https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/debs/ vscodium main' | tee /etc/apt/sources.list.d/vscodium.list

apt-get --no-install-recommends update
apt-get --no-install-recommends install -y codium

# Set-up all users
for dir in $(ls -1d /home/* 2>/dev/null ||:)
do
	# Disable most of the telemetry and auto-updates
	mkdir -p "$dir/.config/Code/User"
	mkdir -p "$dir/.config/VSCodium/User"
	cat <<-'EOF' | tee \
		"$dir/.config/Code/User/settings.json" \
		"$dir/.config/VSCodium/User/settings.json"
	{
	    "extensions.autoCheckUpdates": false,
	    "extensions.autoUpdate": false,
	    "json.schemaDownload.enable": false,
	    "npm.fetchOnlinePackageInfo": false,
	    "settingsSync.keybindingsPerPlatform": false,
	    "telemetry.enableCrashReporter": false,
	    "telemetry.enableTelemetry": false,
	    "update.enableWindowsBackgroundUpdates": false,
	    "update.mode": "none",
	    "update.showReleaseNotes": false,
	    "workbench.enableExperiments": false,
	    "workbench.settings.enableNaturalLanguageSearch": false
	}
	EOF

	# Fix rights
	usr=$(echo "$dir" | rev | cut -d/ -f1 | rev)
	chown -R "$usr:$usr" "$dir" ||:
done

# Install Go extension and tools

sudo -iu student code --install-extension golang.go
sudo -iu student go get github.com/01-edu/z01
sudo -iu student go get github.com/uudashr/gopkgs/v2/cmd/gopkgs
sudo -iu student go get github.com/ramya-rao-a/go-outline
sudo -iu student go get github.com/cweill/gotests/gotests
sudo -iu student go get github.com/fatih/gomodifytags
sudo -iu student go get github.com/josharian/impl
sudo -iu student go get github.com/haya14busa/goplay/cmd/goplay
sudo -iu student go get github.com/go-delve/delve/cmd/dlv
sudo -iu student go get github.com/go-delve/delve/cmd/dlv@master
sudo -iu student go get honnef.co/go/tools/cmd/staticcheck
sudo -iu student go get golang.org/x/tools/gopls

# Install LibreOffice

apt-get --no-install-recommends -y install libreoffice

# Install Docker

apt-get --no-install-recommends -y install apt-transport-https ca-certificates curl gnupg2 software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository --yes "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get --no-install-recommends update
apt-get --no-install-recommends -y install docker-ce docker-ce-cli containerd.io
adduser student docker

# Install Docker compose
curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
curl -L https://raw.githubusercontent.com/docker/compose/1.29.1/contrib/completion/bash/docker-compose -o /etc/bash_completion.d/docker-compose

# Purge unused Ubuntu packages
pkgs="
apparmor
apport
bind9
bolt
cups*
exim*
fprintd
friendly-recovery
gnome-initial-setup
gnome-online-accounts
gnome-power-manager
gnome-software
gnome-software-common
memtest86+
orca
popularity-contest
python3-update-manager
secureboot-db
snapd
speech-dispatcher*
spice-vdagent
ubuntu-report
ubuntu-software
unattended-upgrades
update-inetd
update-manager-core
update-notifier
update-notifier-common
whoopsie
xdg-desktop-portal
"

# shellcheck disable=2086
apt-get -y purge $pkgs
apt-get -y autoremove --purge

# Install packages
pkgs="$(cat common_packages.txt)
baobab
blender
dconf-editor
emacs
f2fs-tools
firefox
gimp
gnome-calculator
gnome-system-monitor
gnome-tweaks
i3lock
imagemagick
mpv
vim
virtualbox
xfsprogs
zenity
xdotool
libglib2.0-dev-bin
"

# shellcheck disable=2086
apt-get --no-install-recommends -y install $pkgs


# Install Rust
sudo -iu student curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- "-y"


# Disable services
services="
apt-daily-upgrade.timer
apt-daily.timer
console-setup.service
e2scrub_reap.service
keyboard-setup.service
motd-news.timer
remote-fs.target
"
# shellcheck disable=2086
systemctl disable $services

services="
grub-common.service
plymouth-quit-wait.service
"
# shellcheck disable=2086
systemctl mask $services

# Logout quickly
cat <<EOF >>/etc/systemd/logind.conf
KillUserProcesses=yes
UserStopDelaySec=0
EOF

# Disable GTK hidden scroll bars
echo GTK_OVERLAY_SCROLLING=0 >> /etc/environment

# Reveal boot messages
sed -i -e 's/TTYVTDisallocate=yes/TTYVTDisallocate=no/g' /etc/systemd/system/getty.target.wants/getty@tty1.service

# Speedup boot
sed -i 's/MODULES=most/MODULES=dep/g' /etc/initramfs-tools/initramfs.conf
sed -i 's/COMPRESS=gzip/COMPRESS=lz4/g' /etc/initramfs-tools/initramfs.conf

# Reveal autostart services
sed -i 's/NoDisplay=true/NoDisplay=false/g' /etc/xdg/autostart/*.desktop

# Remove password complexity constraints
sed -i 's/ obscure / minlen=1 /g' /etc/pam.d/common-password

# Remove splash screen (plymouth)
sed -i 's/quiet splash/quiet/g' /etc/default/grub

# Disable Wayland (solves slow navbar issue)
sed -i -e 's/#WaylandEnable/WaylandEnable/g' /etc/gdm3/custom.conf

update-initramfs -u
update-grub

# Change ext4 default mount options
sed -i -e 's/ errors=remount-ro/ noatime,nodelalloc,errors=remount-ro/g' /etc/fstab

# Disable swapfile
swapoff /swapfile ||:
rm -f /swapfile
sed -i '/swapfile/d' /etc/fstab

# Put temporary and cache folders as tmpfs
echo 'tmpfs /tmp tmpfs defaults,noatime,rw,nosuid,nodev,mode=1777,size=1G 0 0' >> /etc/fstab

# Install additional drivers
ubuntu-drivers install ||:

# Copy system files

cp -r system /tmp
cd /tmp/system

test -v PERSISTENT && rm -rf etc/gdm3 usr/share/initramfs-tools

# Overwrite with custom files from Git repository
if test -v OVERWRITE; then
	folder=$(echo "$OVERWRITE" | cut -d';' -f1)
	url=$(echo "$OVERWRITE" | cut -d';' -f2)
	if git ls-remote -q "$url" &>/dev/null; then
		tmp=$(mktemp -d)
		git clone --depth 1 "$url" "$tmp"
		rm -rf "$tmp"/.git
		cp -aT "$tmp" "$folder"
		rm -rf "$tmp"
	fi
fi

# Fix permissions
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
find . -type f -exec /bin/sh -c "file {} | grep -q 'shell script' && chmod +x {}" \;
find . -type f -exec /bin/sh -c "file {} | grep -q 'public key' && chmod 400 {}" \;

sed -i -e "s|::DISK::|$disk|g" etc/udev/rules.d/10-local.rules

# Generate wallpaper
cd usr/share/backgrounds/01
test ! -e wallpaper.png && composite logo.png background.png wallpaper.png
cd /tmp/system

cp --preserve=mode -RT . /

cd /usr/local/src/format
PATH=$PATH:/usr/local/go/bin
go mod download
go build -o /usr/local/bin/format

cd "$script_dir"

# Prepare default login screen background
# Autor: Thiago Silva
# Contact: thiagos.dasilva@gmail.com
# URL: https://github.com/thiggy01/ubuntu-20.04-change-gdm-background
# =================================================================== #

# Assign the default gdm theme file path.
gdm3Resource=/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource

# Create a backup file of the original theme if there isn't one.
[ ! -f "$gdm3Resource"~ ] && cp "$gdm3Resource" "$gdm3Resource~"

gdm3xml=$(basename "$gdm3Resource").xml
workDir="/tmp/gdm3-theme"
gdmBgImg=$(realpath "/usr/share/backgrounds/01/wallpaper.png")
imgFile=$(basename "$gdmBgImg")
for resource in `gresource list "$gdm3Resource~"`; do
    resource="${resource#\/org\/gnome\/shell\/}"
    if [ ! -d "$workDir"/"${resource%/*}" ]; then
        mkdir -p "$workDir"/"${resource%/*}"
    fi
done

# Extract resources from binary file.
for resource in `gresource list "$gdm3Resource~"`; do
    gresource extract "$gdm3Resource~" "$resource" > \
    "$workDir"/"${resource#\/org\/gnome\/shell\/}"
done

# Copy selected image to the resources directory.
cp "$gdmBgImg" "$workDir"/theme
# Change gdm background to the image you submited.
oldImg="#lockDialogGroup \{.*?\}"
newImg="#lockDialogGroup {
    background: url('resource:\/\/\/org\/gnome\/shell\/theme\/$imgFile');
    background-size: cover; }"
perl -i -0777 -pe "s/$oldImg/$newImg/s" "$workDir"/theme/gdm3.css

# Generate gresource xml file.
echo '<?xml version="1.0" encoding="UTF-8"?>
<gresources>
<gresource prefix="/org/gnome/shell/theme">' > "$workDir"/theme/"$gdm3xml"
for file in `gresource list "$gdm3Resource~"`; do
    echo "        <file>${file#\/org\/gnome/shell\/theme\/}</file>" \
    >> "$workDir"/theme/"$gdm3xml"
done
echo "        <file>$imgFile</file>" >> "$workDir"/theme/"$gdm3xml"
echo '    </gresource>
</gresources>' >> "$workDir"/theme/"$gdm3xml"

# Compile resources into a gresource binary file.
glib-compile-resources --sourcedir=$workDir/theme/ $workDir/theme/"$gdm3xml"
# Move the generated binary file to the gnome-shell folder.
mv $workDir/theme/gnome-shell-theme.gresource $gdm3Resource
# Check if gresource was sucessfuly moved to its default folder.
chmod 644 "$gdm3Resource"
# Remove temporary directories and files.
rm -r "$workDir"

cd $script_dir
rm -rf /tmp/system

if ! test -v PERSISTENT; then
	sgdisk --new 0:0:+32G "$disk"
	sgdisk --new 0:0:+32G "$disk"
	sgdisk --largest-new 0 "$disk"
	sgdisk --change-name 3:01-tmp-home "$disk"
	sgdisk --change-name 4:01-docker "$disk"
	sgdisk --change-name 5:01-tmp-system "$disk"

	# Add Docker persistent partition
	partprobe
	mkfs.ext4 -E lazy_journal_init,lazy_itable_init=0 /dev/disk/by-partlabel/01-docker
	echo 'PARTLABEL=01-docker /var/lib/docker ext4 noatime,errors=remount-ro 0 2' >> /etc/fstab
	systemctl stop docker.service containerd.service
	mv /var/lib/docker /tmp
	mkdir /var/lib/docker
	mount /dev/disk/by-partlabel/01-docker
	mv /tmp/docker/* /var/lib/docker
	umount /var/lib/docker

	# Remove fsck because the system partition will be read-only (overlayroot)
	rm /usr/share/initramfs-tools/hooks/fsck

	apt-get --no-install-recommends -y install overlayroot
	echo 'overlayroot="device:dev=/dev/disk/by-partlabel/01-tmp-system,recurse=0"' >> /etc/overlayroot.conf

	update-initramfs -u

	# Lock root password
	passwd -l root

	# Disable user password
	passwd -d student

	# Remove tty
	cat <<-"EOF">> /etc/systemd/logind.conf
	NAutoVTs=0
	ReserveVT=N
	EOF

	# Remove user abilities
	sed -i 's/^%admin/# &/' /etc/sudoers
	sed -i 's/^%sudo/# &/' /etc/sudoers
	gpasswd -d student lpadmin
	gpasswd -d student sambashare

	# Give to rights to use format tool
	echo 'student ALL = (root) NOPASSWD: /usr/local/bin/format' >> /etc/sudoers

	cp /etc/shadow /etc/shadow-
fi

# Use Cloudflare DNS server
echo 'supersede domain-name-servers 1.1.1.1;' >> /etc/dhcp/dhclient.conf

# Clean system

# Purge useless packages
apt-get -y autoremove --purge
apt-get autoclean
apt-get clean
apt-get install

rm -rf /root/.local

# Remove connection logs
echo > /var/log/lastlog
echo > /var/log/wtmp
echo > /var/log/btmp

# Remove machine ID
echo > /etc/machine-id

# Remove logs
cd /var/log
rm -rf alternatives.log*
rm -rf apt/*
rm -rf auth.log
rm -rf dpkg.log*
rm -rf gpu-manager.log
rm -rf installer
rm -rf journal/d6e982aa8c9d4c1dbcbdcff195642300
rm -rf kern.log
rm -rf syslog
rm -rf sysstat

# Remove random seeds
rm -rf /var/lib/systemd/random-seed
rm -rf /var/lib/NetworkManager/secret_key

# Remove network configs
rm -rf /etc/NetworkManager/system-connections/*
rm -rf /var/lib/bluetooth/*
rm -rf /var/lib/NetworkManager/*

# Remove caches
rm -rf /var/lib/gdm3/.cache/*
rm -rf /root/.cache
rm -rf /home/student/.cache

rm -rf /home/student/.sudo_as_admin_successful /home/student/.bash_logout

rm -rf /tmp/*
rm -rf /tmp/.* ||:
