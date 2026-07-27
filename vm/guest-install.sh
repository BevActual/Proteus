#!/usr/bin/env bash
# Unattended Arch install for Proteus test VM (run from live ISO as root).
set -euo pipefail

DISK="${DISK:-/dev/vda}"
HOSTNAME="${HOSTNAME:-proteus}"
USERNAME="${USERNAME:-andrew}"
PASSWORD="${PASSWORD:-proteus}"
TZ="${TZ:-UTC}"

export DEBIAN_FRONTEND=noninteractive

echo "==> Waiting for network"
for i in $(seq 1 60); do
  if ping -c1 -W2 archlinux.org >/dev/null 2>&1 || curl -fsS --max-time 3 https://archlinux.org >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

timedatectl set-ntp true || true

echo "==> Partitioning ${DISK}"
sgdisk -Z "${DISK}" || true
sgdisk -n1:0:+1G -t1:EF00 -c1:ESP "${DISK}"
sgdisk -n2:0:0 -t2:8300 -c2:root "${DISK}"
partprobe "${DISK}" || true
sleep 1

# virtio names: vda1/vda2 (or nvme etc.)
P1="${DISK}1"
P2="${DISK}2"
if [[ ! -b "$P1" ]]; then
  P1="${DISK}p1"
  P2="${DISK}p2"
fi

echo "==> Formatting"
mkfs.fat -F32 -n ESP "$P1"
mkfs.ext4 -F -L root "$P2"

echo "==> Mounting"
mount "$P2" /mnt
mount --mkdir "$P1" /mnt/boot

echo "==> pacstrap (base system)"
# Preselect mkinitcpio as initramfs provider (avoid interactive prompt)
pacman -Sy --noconfirm archlinux-keyring || true
# Force noninteractive pacstrap; feed default provider choice
printf '\n' | pacstrap -K /mnt \
  base linux linux-firmware mkinitcpio \
  networkmanager openssh sudo \
  vim nano less \
  dosfstools efibootmgr \
  git

echo "==> fstab"
genfstab -U /mnt >> /mnt/etc/fstab

ROOT_UUID="$(blkid -s UUID -o value "$P2")"

echo "==> Configuring chroot"
arch-chroot /mnt /bin/bash -euo pipefail <<CHROOT
ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo '${HOSTNAME}' > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo 'root:${PASSWORD}' | chpasswd
id ${USERNAME} >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash ${USERNAME}
echo '${USERNAME}:${PASSWORD}' | chpasswd
mkdir -p /etc/sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

systemctl enable NetworkManager.service
systemctl enable sshd.service

bootctl install
cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 3
console-mode keep
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux (Proteus)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw
ENTRY

# Ensure SSH allows password auth for test VM
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

mkdir -p /mnt/proteus
cat > /etc/systemd/system/mnt-proteus.mount <<'MOUNT'
[Unit]
Description=Proteus 9p host share
After=network-online.target

[Mount]
What=proteus
Where=/mnt/proteus
Type=9p
Options=trans=virtio,version=9p2000.L,msize=262144,_netdev

[Install]
WantedBy=multi-user.target
MOUNT
# Do not enable by default — document manual mount; optional enable later
CHROOT

sync
echo "==> Install complete. Ready to reboot."
