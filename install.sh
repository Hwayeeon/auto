#!/bin/bash

# This script installs Arch Linux automatically with KDE Plasma desktop environment.
# It is intended to be run from an Arch Linux live environment.
# It is recommended to run this script in a virtual machine first to test it.
# This script is provided as-is and the author is not responsible for any damage caused by its use.
# Use at your own risk.

# Variables - CONFIGURE THESE BEFORE RUNNING
DISK="/dev/nvme0n1"         # Change this to your target disk
HOSTNAME="archlinux"        # Change this to your desired hostname
USERNAME="user"             # Change this to your desired username
ROOT_PASSWORD="123"         # Root password
USER_PASSWORD="123"         # User password
TIMEZONE="Asia/Jakarta"     # Change this to your desired timezone
LOCALE="en_US.UTF-8"        # Change this to your desired locale
KEYMAP="us"                 # Change this to your desired keymap
ETHERNET_INTERFACE="enp0s3" # Change this after checking with 'ip a'
CPU_TYPE="amd"              # Change to "intel" for Intel CPUs

# Partition variables (set if partitions already created manually)
EFI_PARTITION="${DISK}p1"
ROOT_PARTITION="${DISK}p2"

# Pre-Installation Steps
echo "Starting Arch Linux Installation with KDE Plasma"

# Update mirror list with fastest mirrors for Indonesia
echo "Updating mirror list..."
reflector --country 'Indonesia' --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# NOTE: Manual partitioning required before running this script
# Run these commands manually:
# wipefs -a /dev/nvme0n1
# cfdisk /dev/nvme0n1
# Create:
#   - Partition 1: EFI System (512M-1G)
#   - Partition 2: Linux filesystem (remaining space)

# Format Partitions
echo "Formatting partitions..."
mkfs.vfat -F 32 $EFI_PARTITION
mkfs.ext4 $ROOT_PARTITION

# Mount Partitions
echo "Mounting partitions..."
mount $ROOT_PARTITION /mnt
mkdir -p /mnt/boot/efi
mkdir -p /mnt/home
mount $EFI_PARTITION /mnt/boot/efi

# Generate fstab
echo "Creating directory structure and generating fstab..."
mkdir -p /mnt/etc
genfstab -U -p /mnt >> /mnt/etc/fstab

# Install Base System
echo "Installing base system..."
pacstrap -K /mnt base linux linux-firmware

# Install Essential Packages
echo "Installing essential packages..."
# Install CPU microcode based on CPU type
if [ "$CPU_TYPE" == "amd" ]; then
    MICROCODE="amd-ucode"
else
    MICROCODE="intel-ucode"
fi

arch-chroot /mnt pacman -S --noconfirm $MICROCODE sof-firmware grub sudo efibootmgr base-devel git nano cpupower

# Install Xorg and Audio
echo "Installing Xorg and audio packages..."
arch-chroot /mnt pacman -S --noconfirm xorg xorg-xinit pulseaudio pavucontrol

# Install KDE Plasma Desktop Environment
echo "Installing KDE Plasma..."
arch-chroot /mnt pacman -S --noconfirm plasma-meta kde-applications sddm

# Configure System
echo "Configuring system..."

# Set CPU governor to performance
arch-chroot /mnt bash -c "echo 'governor=\"performance\"' > /etc/default/cpupower"
arch-chroot /mnt systemctl enable cpupower

# Enable SDDM display manager
arch-chroot /mnt systemctl enable sddm

# Compile kernel
arch-chroot /mnt mkinitcpio -p linux

# Set root password
echo "Setting root password..."
arch-chroot /mnt bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Create user
echo "Creating user: $USERNAME"
arch-chroot /mnt useradd -m -g users -G wheel $USERNAME
arch-chroot /mnt bash -c "echo '$USERNAME:$USER_PASSWORD' | chpasswd"

# Enable sudo for wheel group
arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Install and configure GRUB bootloader
echo "Installing GRUB bootloader..."
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id="Arch Linux" --recheck
arch-chroot /mnt sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/' /etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Disable journald logging (optional - for minimal systems)
# arch-chroot /mnt sed -i 's/#Storage=auto/Storage=none/' /etc/systemd/journald.conf

# Post-Installation Configuration
echo "Configuring post-installation settings..."

# Set DNS servers
cat > /mnt/etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Configure static IP (modify according to your network)
cat > /mnt/etc/systemd/network/$ETHERNET_INTERFACE.network << EOF
[Match]
Name=$ETHERNET_INTERFACE

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
EOF

# Enable networkd
arch-chroot /mnt systemctl enable systemd-networkd

# Set hostname
arch-chroot /mnt bash -c "echo '$HOSTNAME' > /etc/hostname"

# Configure locale
arch-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt bash -c "echo 'LANG=$LOCALE' > /etc/locale.conf"

# Set timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
arch-chroot /mnt hwclock --systohc

# Set keymap
arch-chroot /mnt bash -c "echo 'KEYMAP=$KEYMAP' > /etc/vconsole.conf"

# Enable NTP
arch-chroot /mnt timedatectl set-ntp true

# Cleanup
echo "Cleaning up..."
arch-chroot /mnt pacman -Scc --noconfirm

# Installation Complete
echo "========================================="
echo "Installation completed successfully!"
echo "========================================="
echo ""
echo "Please review the following before rebooting:"
echo "1. Check /mnt/etc/fstab for correct partition UUIDs"
echo "2. Verify network interface name in /mnt/etc/systemd/network/"
echo "3. Update static IP configuration if needed"
echo ""
echo "To complete installation:"
echo "1. Exit the chroot environment (if inside)"
echo "2. Run: umount -R /mnt"
echo "3. Run: reboot"
echo ""
echo "After reboot:"
echo "- Login as root or $USERNAME"
echo "- SDDM should start automatically and load KDE Plasma"
echo "- Check network with: ip a"
echo "========================================="