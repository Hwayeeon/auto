#!/bin/bash

################################################################################
# Automatic Arch Linux Installation Script with KDE Plasma
# This script automates the installation of Arch Linux with KDE Plasma Desktop
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

################################################################################
# Configuration Variables
################################################################################

DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-archbox}"
USERNAME="${USERNAME:-testing}"
PASSWORD="${PASSWORD:-123}"
TIMEZONE="${TIMEZONE:-Asia/Jakarta}"
LOCALE="${LOCALE:-en_US.UTF-8}"
SWAPSIZE="${SWAPSIZE:-2G}"
EFI_SIZE="${EFI_SIZE:-512MiB}"

################################################################################
# Color Output Functions
################################################################################

print_info() {
    echo -e "\e[1;34m[INFO]\e[0m $1"
}

print_success() {
    echo -e "\e[1;32m[SUCCESS]\e[0m $1"
}

print_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
}

print_warning() {
    echo -e "\e[1;33m[WARNING]\e[0m $1"
}

################################################################################
# Disk Partitioning
################################################################################

partition_disk() {
    print_info "Partitioning disk: $DISK"
    
    # Clear existing partition table and create GPT
    parted -s "$DISK" mklabel gpt
    
    # Create EFI partition
    parted -s "$DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
    parted -s "$DISK" set 1 esp on
    
    # Create root partition
    parted -s "$DISK" mkpart primary ext4 "$EFI_SIZE" 100%
    
    print_success "Disk partitioned successfully"
}

################################################################################
# Format Partitions
################################################################################

format_partitions() {
    print_info "Formatting partitions..."
    
    # Format EFI partition
    mkfs.vfat -F 32 "${DISK}1"
    
    # Format root partition
    mkfs.ext4 -F "${DISK}2"
    
    print_success "Partitions formatted successfully"
}

################################################################################
# Mount Partitions
################################################################################

mount_partitions() {
    print_info "Mounting partitions..."
    
    # Mount root partition
    mount "${DISK}2" /mnt
    
    # Create and mount EFI partition
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi
    
    # Create home directory
    mkdir -p /mnt/home
    
    print_success "Partitions mounted successfully"
}

################################################################################
# Install Base System
################################################################################

install_base_system() {
    print_info "Installing base system..."
    
    pacstrap -K /mnt base linux linux-firmware
    
    print_success "Base system installed successfully"
}

################################################################################
# Generate Fstab
################################################################################

generate_fstab() {
    print_info "Generating fstab..."
    
    genfstab -U /mnt >> /mnt/etc/fstab
    
    print_success "Fstab generated successfully"
}

################################################################################
# Configure System (runs inside chroot)
################################################################################

configure_system() {
    print_info "Configuring system..."
    
    # Create configuration script to run inside chroot
    cat > /mnt/root/configure.sh <<'CHROOT_EOF'
#!/bin/bash
set -e
set -u

# Import variables
HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
PASSWORD="__PASSWORD__"
TIMEZONE="__TIMEZONE__"
LOCALE="__LOCALE__"
SWAPSIZE="__SWAPSIZE__"

echo "[INFO] Installing essential packages..."
pacman -S --noconfirm \
    base-devel \
    efibootmgr \
    grub \
    networkmanager \
    git \
    wget \
    curl \
    neovim \
    nano \
    man-db \
    man-pages

echo "[INFO] Detecting and installing CPU microcode..."
if lscpu | grep -qi intel; then
    pacman -S --noconfirm intel-ucode
elif lscpu | grep -qi amd; then
    pacman -S --noconfirm amd-ucode
fi

echo "[INFO] Installing KDE Plasma Desktop Environment..."
pacman -S --noconfirm \
    plasma-meta \
    konsole \
    dolphin \
    kate \
    ark \
    spectacle \
    gwenview \
    okular \
    firefox \
    sddm \
    sddm-kcm

echo "[INFO] Setting root password..."
echo "root:$PASSWORD" | chpasswd

echo "[INFO] Creating user: $USERNAME"
useradd -m -G wheel,storage,power,audio,video -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

echo "[INFO] Configuring sudo privileges..."
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$USERNAME"
chmod 440 /etc/sudoers.d/"$USERNAME"

echo "[INFO] Setting hostname..."
echo "$HOSTNAME" > /etc/hostname

echo "[INFO] Configuring hosts file..."
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

echo "[INFO] Configuring timezone..."
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
hwclock --systohc

echo "[INFO] Configuring locale..."
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "[INFO] Generating initramfs..."
mkinitcpio -P

echo "[INFO] Installing and configuring GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Arch Linux" --recheck
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "[INFO] Creating and configuring swapfile..."
fallocate -l "$SWAPSIZE" /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap defaults 0 0' >> /etc/fstab

echo "[INFO] Enabling essential services..."
systemctl enable NetworkManager
systemctl enable sddm

echo "[INFO] Configuring Neovim as default editor..."
echo "export EDITOR=nvim" >> /etc/profile
echo "export VISUAL=nvim" >> /etc/profile

echo "[INFO] Creating user Neovim configuration directory..."
mkdir -p /home/"$USERNAME"/.config/nvim
cat > /home/"$USERNAME"/.config/nvim/init.vim <<NVIM_EOF
" Basic Neovim Configuration
set number
set relativenumber
set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
set mouse=a
set clipboard=unnamedplus
syntax on
filetype plugin indent on
NVIM_EOF
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.config

echo "[INFO] Optimizing journald logs..."
sed -i 's/^#Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=50M/' /etc/systemd/journald.conf

echo "[SUCCESS] System configuration completed!"
CHROOT_EOF

    # Replace placeholders with actual values
    sed -i "s|__HOSTNAME__|$HOSTNAME|g" /mnt/root/configure.sh
    sed -i "s|__USERNAME__|$USERNAME|g" /mnt/root/configure.sh
    sed -i "s|__PASSWORD__|$PASSWORD|g" /mnt/root/configure.sh
    sed -i "s|__TIMEZONE__|$TIMEZONE|g" /mnt/root/configure.sh
    sed -i "s|__LOCALE__|$LOCALE|g" /mnt/root/configure.sh
    sed -i "s|__SWAPSIZE__|$SWAPSIZE|g" /mnt/root/configure.sh
    
    # Make script executable
    chmod +x /mnt/root/configure.sh
    
    # Run configuration script inside chroot
    arch-chroot /mnt /root/configure.sh
    
    # Clean up
    rm /mnt/root/configure.sh
    
    print_success "System configured successfully"
}

################################################################################
# Cleanup and Finish
################################################################################

finish_installation() {
    print_info "Finishing installation..."
    
    # Unmount all partitions
    umount -R /mnt
    
    print_success "Installation completed successfully!"
    print_info "System will reboot in 5 seconds..."
    sleep 5
    reboot
}

################################################################################
# Main Installation Process
################################################################################

main() {
    print_info "Starting Arch Linux installation with KDE Plasma..."
    print_warning "This will erase all data on $DISK!"
    
    # Run installation steps
    partition_disk
    format_partitions
    mount_partitions
    install_base_system
    generate_fstab
    configure_system
    finish_installation
}

# Execute main function
main