#!/usr/bin/env bash

# DEPENDENCIES
# qemu-user-static is required to run arm software using the "qemu-arm-static" command (I suppose you use this script on a X86_64 computer)
# Please install it via your package manager (e.g. Ubuntu) or whatever way is appropriate for your distribution (Arch has it in AUR)

# BASIC CONIGURATION
# REPO: The Alpine repository to use, you can leave it like it is
# MNT: Where you want to mount the image, just make sure /mnt/alpine isn't already used
# IMAGE: The path and name of the image file to be created, you can leave it as is
# IMAGESIZE: How big you want the image to be. If you want to install Chromium, a evince etc. you should go for at least 1400MB
# ALPINESETUP: This are the commands executed inside the Alpine container to set it up. Most notably it installs XFCE desktop environment,
#              and creates a user named "alpine" with password "alpine". The last command is "sh", which allows you to examine the
#              created image/install more packages/whatever. To finish the script just leave the sh shell with "exit"
# STARGUI: This is the script that gets executed inside the container when the GUI is started. Xepyhr is used to render the desktop
#          inside a window, that has the correct name to be displayed in fullscreen by the kindle's awesome windowmanager
REPO="http://ap.edge.kernel.org/alpine"
ARCH="armv7"
MNT="/mnt/alpine"
IMAGE="./alpine.img"
IMAGESIZE=2048 #Megabytes
ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 8.8.8.8\" > /etc/resolv.conf
mkdir /run/dbus
apk update
apk upgrade
cat /etc/alpine-release
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano
apk add mate-session-manager mate-control-center mate-settings-daemon mate-panel mate-menus mate-desktop mate-themes caja caja-extensions mate-terminal mate-applets mate-screensaver mate-polkit mate-notification-daemon gvfs
apk add font-dejavu font-terminus font-noto font-noto-cjk font-ipa font-jis-misc font-misc-cyrillic
apk add onboard chromium
cp -R /usr/share/icons/HighContrast/. /usr/share/icons/ContrastHigh/.
gtk-update-icon-cache -f /usr/share/icons/ContrastHigh
adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo
su alpine -c \"cd ~
cp -R /tmp/alpine_kindle_dotfiles/. .
dbus-launch dconf load /org/mate/ < ~/.config/org_mate.dconf.dump
dbus-launch dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump
rm ~/.config/*.dump\"

echo '
mouseid=\"\$(env DISPLAY=:1 xinput list --id-only \"Xephyr virtual mouse\")\"
CHROMIUM_FLAGS='\''--force-device-scale-factor=2 --touch-devices='\''\$mouseid'\'' --pull-to-refresh=1 --disable-smooth-scrolling --enable-low-end-device-mode --disable-login-animations --disable-modal-animations --wm-window-animations-disabled --animation-duration-scale=0 --start-maximized'\''' > /etc/chromium/chromium.conf
"
STARTGUI='#!/bin/sh
chmod a+w /dev/shm
cd /home/alpine
SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -nocursor -ac -br -screen $SIZE -cc 4 -reset -terminate & sleep 3 && su alpine -c "env DISPLAY=:1 mate-session"
killall Xephyr'


# ENSURE ROOT
# This script needs root access to e.g. mount the image
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"


# GETTING APK-TOOLS-STATIC
# This tool is used to bootstrap Alpine Linux. It is hosted in the Alpine repositories like any other package, and we need to
# read in the APKINDEX what version it is currently to get the correct download link. It is extracted in /tmp and deleted
# again at the end of the script
echo "Determining version of apk-tools-static"
curl "$REPO/latest-stable/main/$ARCH/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzf /tmp/APKINDEX.tar.gz -C /tmp
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")" # Grep for the version in APKINDEX
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION # Remove what we downloaded and extracted
echo "Version of apk-tools-static is: $APKVER"
echo "Downloading apk-tools-static"
curl "$REPO/latest-stable/main/$ARCH/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xzf "/tmp/apk-tools-static.apk" -C /tmp # extract apk-tools-static to /tmp


# CREATING IMAGE FILE
# To create the image file, a file full of zeros with the desired size is created using dd. An ext3-filesystem is created in it.
# Also automatic checks are disabled using tune2fs
echo "Creating image file"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE
mkfs.ext3 "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"


# MOUNTING IMAGE
# The mountpoint is created (doesn't matter if it exists already) and the empty ext3-filsystem is mounted in it
echo "Mounting image"
mkdir -p "$MNT"
mount -o loop -t ext3 "$IMAGE" "$MNT"


# BOOTSTRAPPING ALPINE
# Here most of the magic happens. The apk tool we extracted earlier is invoked to create the root filesystem of Alpine inside the
# mounted image. We use the arm-version of it to end up with a root filesystem for arm. Also the "edge" repository is used
# to end up with the newest software, some of which is very useful for Kindles
echo "Bootstrapping Alpine"
/tmp/sbin/apk.static -X "$REPO/latest-stable/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base


# COMPLETE IMAGE MOUNTING FOR CHROOT
# Some more things are needed inside the chroot to be able to work in it (for network connection etc.)
mount -t tmpfs tmpfs "$MNT/tmp"
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"

cp -R $(dirname "$0")/alpine_kindle_dotfiles "$MNT/tmp/"

# CONFIGURE ALPINE
# Some configuration needed
cp /etc/resolv.conf "$MNT/etc/resolv.conf" # Copy resolv from host for internet connection
# Configure repositories for apk (edge main+community+testing for lots of useful and up-to-date software)
mkdir -p "$MNT/etc/apk"
echo "$REPO/latest-stable/main/
$REPO/latest-stable/community/" > "$MNT/etc/apk/repositories"
# Create the script to start the gui
echo "$STARTGUI" > "$MNT/startgui.sh"
chmod +x "$MNT/startgui.sh"


# CHROOT
# Chroot and run the setup as specified at the beginning of the script
echo "Chrooting into Alpine"
chroot /mnt/alpine/ /bin/sh -c "$ALPINESETUP"


# UNMOUNT IMAGE & CLEANUP
# Sync to disc
sync
# Kill remaining processes
kill $(lsof +f -t "$MNT")
# We unmount in reverse order
echo "Unmounting image"
sleep 5
umount "$MNT/tmp"
umount "$MNT/sys"
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT") ]]
do
	echo "Alpine is still mounted, please wait.."
	sleep 3
	umount "$MNT"
done
echo "Alpine unmounted"

# And remove the apk-tools-static which we extracted to /tmp
echo "Cleaning up"
rm /tmp/apk-tools-static.apk
rm -r /tmp/sbin
