#!/bin/bash

set -e

# Color
RED='\033[0;31m'
NC='\033[0m' # No Color

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 1>&2
   exit 1
fi

# Check for enough space on /boot volume
boot_line=$(df -h | grep /boot | head -n 1)
if [ "x${boot_line}" = "x" ]; then
  echo "Warning: /boot volume not found .."
else
  boot_space=$(echo $boot_line | awk '{print $4;}')
  free_space=$(echo "${boot_space%?}")
  unit="${boot_space: -1}"
  if [[ "$unit" = "K" ]]; then
    echo "Error: Not enough space left ($boot_space) on /boot"
    exit 1
  elif [[ "$unit" = "M" ]]; then
    if [ "$free_space" -lt "25" ]; then
      echo "Error: Not enough space left ($boot_space) on /boot"
      exit 1
    fi
  fi
fi

# Detect OS and set variables
if grep -q 'ID=debian' /etc/os-release; then
    OS="debian"
    KERNEL_PKG="raspberrypi-kernel"
    HEADERS_PKG="raspberrypi-kernel-headers"
elif grep -q 'ID=ubuntu' /etc/os-release; then
    OS="ubuntu"
    KERNEL_PKG="linux-raspi"
    HEADERS_PKG="linux-headers-raspi"
else
    echo "Unsupported OS" >&2
    exit 1
fi

# Determine overlay directory
OVERLAYS=/boot/overlays
[ -d /boot/firmware/overlays ] && OVERLAYS=/boot/firmware/overlays

# Check for required commands
for cmd in dtparam dtoverlay; do
  if ! command -v $cmd &>/dev/null; then
    echo "$cmd not found" >&2
    echo "You may need to run ./ubuntu-prerequisite.sh"
    exit 1
  fi
done

# Install required packages
apt-get update
apt-get install -y git dkms i2c-tools libasound2-plugins
apt-get install -y $KERNEL_PKG $HEADERS_PKG

# Get current kernel version
KERNEL_VER=$(uname -r)
HEADERS_VER=$(basename /usr/src/linux-headers-* | cut -d- -f3-)

if [ "$KERNEL_VER" != "$HEADERS_VER" ]; then
  echo "Kernel version mismatch. Please reboot and run this script again."
  exit 1
fi

# Install the module
ver="0.3"
mod="seeed-voicecard"

dkms remove --force -m $mod -v $ver --all 2>/dev/null || true
rm -rf /usr/src/$mod-$ver
mkdir -p /usr/src/$mod-$ver
cp -a ./* /usr/src/$mod-$ver/
dkms add -m $mod -v $ver
dkms build -k $KERNEL_VER -m $mod -v $ver || {
    echo "DKMS build failed" >&2
    exit 1
}
dkms install --force -k $KERNEL_VER -m $mod -v $ver

# Install DTBOs
cp seeed-2mic-voicecard.dtbo $OVERLAYS
cp seeed-4mic-voicecard.dtbo $OVERLAYS
cp seeed-8mic-voicecard.dtbo $OVERLAYS

# Update modules
for module in snd-soc-seeed-voicecard snd-soc-ac108 snd-soc-wm8960; do
    if ! grep -q "^$module" /etc/modules; then
        echo "$module" >> /etc/modules
    fi
done

# Update config
CONFIG=/boot/config.txt
[ -f /boot/firmware/usercfg.txt ] && CONFIG=/boot/firmware/usercfg.txt

sed -i -e 's:#dtparam=i2c_arm=on:dtparam=i2c_arm=on:g' $CONFIG
if ! grep -q '^dtoverlay=seeed-4mic-voicecard' $CONFIG; then
    sed -i '/^dtoverlay=seeed/d' $CONFIG
    echo "dtoverlay=seeed-4mic-voicecard" >> $CONFIG
fi
sed -i '/^dtparam=audio=/d' $CONFIG
grep -q "^dtparam=i2s=on$" $CONFIG || echo "dtparam=i2s=on" >> $CONFIG

# Install config files
mkdir -p /etc/voicecard
cp *.conf /etc/voicecard
cp *.state /etc/voicecard

# Install service
cp seeed-voicecard /usr/bin/
cp seeed-voicecard.service /lib/systemd/system/
systemctl enable seeed-voicecard.service 
systemctl start seeed-voicecard

echo "------------------------------------------------------"
echo "Please reboot your Raspberry Pi to apply all settings"
echo "Enjoy!"
echo "------------------------------------------------------"
```