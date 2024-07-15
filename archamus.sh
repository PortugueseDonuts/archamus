#!/bin/bash

# Set up networking
ping -c 4 archlinux.org

# Update the system clock
timedatectl set-ntp true

# Partition the disks
parted /dev/sda mklabel gpt
parted /dev/sda mkpart primary fat32 1MiB 1200MiB
parted /dev/sda set 1 esp on
parted /dev/sda mkpart primary linux-swap 1200MiB $((efiSize + swapSize))MiB
parted /dev/sda mkpart primary btrfs $((efiSize + swapSize))MiB 100%

# Format the partitions
mkfs.fat -F32 /dev/sda1
mkswap /dev/sda2
swapon /dev/sda2
mkfs.btrfs /dev/sda3

# Mount the filesystem and create subvolumes
mount /dev/sda3 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Remount with subvolumes
mount -o noatime,compress=zstd,subvol=@ /dev/sda3 /mnt
mkdir -p /mnt/{boot,home,var/cache/pacman/pkg,var/log,tmp,srv,.snapshots}
mount -o noatime,compress=zstd,subvol=@home /dev/sda3 /mnt/home
mount -o noatime,compress=zstd,subvol=@pkg /dev/sda3 /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,subvol=@log /dev/sda3 /mnt/var/log
mount -o noatime,compress=zstd,subvol=@tmp /dev/sda3 /mnt/tmp
mount -o noatime,compress=zstd,subvol=@srv /dev/sda3 /mnt/srv
mount -o noatime,compress=zstd,subvol=@snapshots /dev/sda3 /mnt/.snapshots

# Mount the EFI partition
mount /dev/sda1 /mnt/boot

# Install essential packages
pacstrap /mnt base base-devel linux linux-firmware btrfs-progs snapper snap-pac grub efibootmgr amd-ucode networkmanager bash-completion nano snapper-gui

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt

# Set the timezone
ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
hwclock --systohc

# Set the locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "pt_PT.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=pt-latin1" > /etc/vconsole.conf

# Set the hostname
echo "archlinux" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 archlinux.localdomain archlinux" >> /etc/hosts

# Set root password
echo "root:12345" | chpasswd

# Create a new user
useradd -m -G wheel,audio,video -s /bin/bash username
echo "username:54321" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install and configure bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

# Install and configure Snapper
snapper -c root create-config /
snapper -c home create-config /home
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

# Exit chroot
exit

# Unmount and reboot
umount -R /mnt
reboot