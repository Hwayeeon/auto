#!/bin/bash

# Automatic installation script for Arch Linux
# This script will guide you through the installation process
# It assumes you are running it from an Arch Linux live environment
# and have a working internet connection.
# The creator of this script is not responsible for any damage caused by its use.
# Default using KDE Plasma as the desktop environment.

set -e

# Function to get disk size in bytes
get_disk_size() {
    local disk=$1
    lsblk -bdn -o SIZE "$disk" 2>/dev/null || echo "0"
}

# Function to check if disk is removable (USB)
is_removable() {
    local disk=$1
    local disk_name=$(basename "$disk")
    local removable=$(cat "/sys/block/$disk_name/removable" 2>/dev/null || echo "0")
    [[ "$removable" == "1" ]]
}

# Function to check if disk is mounted as root filesystem (Live ISO)
is_boot_disk() {
    local disk=$1
    # Check if any partition of this disk is mounted at /run/archiso/bootmnt
    lsblk -no MOUNTPOINT "$disk" 2>/dev/null | grep -q "/run/archiso/bootmnt"
}

DISK=""
MAX_SIZE=0

# Get all block devices (disks only, not partitions)
for device in $(lsblk -dpno NAME | grep -E '^/dev/(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z])$'); do
    # Skip if removable (USB)
    if is_removable "$device"; then
        echo "Skipping removable device: $device"
        continue
    fi
    
    # Skip if it's the boot disk (Live ISO)
    if is_boot_disk "$device"; then
        echo "Skipping boot disk: $device"
        continue
    fi
    
    # Get disk size
    SIZE=$(get_disk_size "$device")
    
    # Select disk with maximum size
    if (( SIZE > MAX_SIZE )); then
        MAX_SIZE=$SIZE
        DISK=$device
    fi
done

# Check if a disk was found
if [[ -z "$DISK" ]]; then
    echo "ERROR: No suitable disk found for installation!"
    exit 1
fi

# Convert size to human readable format
HUMAN_SIZE=$(lsblk -dno SIZE "$DISK")

echo "Selected disk: $DISK (Size: $HUMAN_SIZE)"
echo "DISK=$DISK"

# Export for use in subsequent installation steps
export DISK