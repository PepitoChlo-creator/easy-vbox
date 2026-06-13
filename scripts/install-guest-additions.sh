#!/usr/bin/env bash
echo "Run these commands INSIDE the VM:"
echo "Then from host: Devices → Insert Guest Additions CD image..."
read -rp "Guest (ubuntu/debian/fedora/arch/kali/windows): " g
case $g in
  ubuntu|debian|kali) echo 'sudo apt update && sudo apt install -y build-essential dkms linux-headers-$(uname -r) && sudo mkdir -p /mnt/cdrom && sudo mount /dev/cdrom /mnt/cdrom && sudo /mnt/cdrom/VBoxLinuxAdditions.run && sudo reboot' ;;
  *) echo "Insert CD and run installer inside guest, then reboot." ;;
esac
