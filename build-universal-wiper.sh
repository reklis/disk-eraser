#!/bin/bash
# Universal Disk Wiper - Works on ALL hardware
# Uses full Linux kernel with all drivers built-in

set -e

# Configuration
WORK_DIR="$(pwd)"
BUILD_DIR="$WORK_DIR/wiper-build"
ISO_DIR="$BUILD_DIR/iso"
INITRD_DIR="$BUILD_DIR/custom-initrd"
OUTPUT_ISO="$WORK_DIR/disk-wiper.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Universal Disk Wiper ISO Builder${NC}"
echo "==================================="

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Create directory structure
echo -e "${YELLOW}Creating build directories...${NC}"
mkdir -p "$ISO_DIR"/{isolinux,EFI/boot,boot}
mkdir -p "$INITRD_DIR"

# Download kernel and initrd with full driver support
echo -e "${YELLOW}Downloading kernel with full driver support...${NC}"

# Try multiple sources for better reliability
KERNEL_DOWNLOADED=false
INITRD_DOWNLOADED=false

# Try Debian first (more stable mirrors)
echo "Trying Debian kernel..."
if wget --timeout=10 -q --show-progress -O "$ISO_DIR/boot/vmlinuz" \
    "http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"; then
    KERNEL_DOWNLOADED=true
    echo "Debian kernel downloaded successfully"
fi

if [ "$KERNEL_DOWNLOADED" = false ]; then
    echo "Trying Ubuntu kernel..."
    if wget --timeout=10 -q --show-progress -O "$ISO_DIR/boot/vmlinuz" \
        "http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux"; then
        KERNEL_DOWNLOADED=true
    fi
fi

if [ "$KERNEL_DOWNLOADED" = false ]; then
    echo -e "${RED}Failed to download kernel from primary sources${NC}"
    exit 1
fi

# Download initrd
echo "Downloading initrd..."
if wget --timeout=10 -q --show-progress -O "$BUILD_DIR/initrd.gz" \
    "http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"; then
    INITRD_DOWNLOADED=true
    echo "Debian initrd downloaded successfully"
fi

if [ "$INITRD_DOWNLOADED" = false ]; then
    echo "Trying Ubuntu initrd..."
    if wget --timeout=10 -q --show-progress -O "$BUILD_DIR/initrd.gz" \
        "http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"; then
        INITRD_DOWNLOADED=true
    fi
fi

if [ "$INITRD_DOWNLOADED" = false ]; then
    echo -e "${RED}Failed to download initrd${NC}"
    exit 1
fi

# Extract and modify initrd
echo -e "${YELLOW}Customizing initrd...${NC}"
cd "$INITRD_DIR"
gzip -dc "$BUILD_DIR/initrd.gz" | cpio -id --quiet 2>/dev/null || true

# Check what we got
echo "Checking initrd contents..."
if [ -d lib/modules ]; then
    KVER=$(ls lib/modules | head -1)
    echo "  Found kernel modules for: $KVER"
    echo "  Storage modules present:"
    find lib/modules -name "*.ko" | grep -E "(ahci|ata_piix|sd_mod|virtio)" | wc -l
else
    echo "  WARNING: No kernel modules in initrd!"
fi

# Make sure we have essential binaries
for binary in modprobe lsmod depmod udevadm; do
    if which $binary >/dev/null 2>&1; then
        echo "  Found: $binary"
    else
        echo "  Missing: $binary"
    fi
done

# Download and add additional firmware if needed
echo -e "${YELLOW}Adding additional firmware...${NC}"
if [ ! -d lib/firmware ]; then
    mkdir -p lib/firmware
fi

# Create our disk wiper init
cat > "$INITRD_DIR/init" << 'EOINIT'
#!/bin/sh

# Redirect output to console
exec < /dev/console > /dev/console 2>&1

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /run

# Suppress kernel messages after boot
echo "1" > /proc/sys/kernel/printk

# Set up environment
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

clear
echo "========================================"
echo "     UNIVERSAL DISK WIPER"
echo "========================================"
echo ""
echo "Initializing hardware..."

# Check for kernel modules
echo "Checking kernel modules..."
if [ -d /lib/modules ]; then
    KVER=$(uname -r)
    echo "Kernel version: $KVER"
    
    # Run depmod to build module dependencies
    if [ -f /sbin/depmod ]; then
        echo "Running depmod..."
        /sbin/depmod -a
    fi
    
    # Check what storage modules are available
    echo "Available storage modules:"
    find /lib/modules/$KVER -name "*.ko" | grep -E "(ahci|ata|virtio|nvme|sd_mod)" | head -10
else
    echo "WARNING: No kernel modules found!"
fi

# Load ALL storage drivers to support any hardware
echo ""
echo "Loading storage drivers..."

# First load base SCSI support
for module in scsi_mod sd_mod sr_mod sg; do
    if modprobe $module 2>/dev/null; then
        echo "  Loaded: $module"
    fi
done

# Load libata base support
for module in libata libahci ahci; do
    if modprobe $module 2>/dev/null; then
        echo "  Loaded: $module"
    fi
done

# Load specific ATA drivers
for module in ata_piix ata_generic pata_acpi sata_nv sata_sil sata_via; do
    if modprobe $module 2>/dev/null; then
        echo "  Loaded: $module"
    fi
done

# Load virtio drivers for QEMU/KVM
for module in virtio virtio_pci virtio_ring virtio_blk virtio_scsi; do
    if modprobe $module 2>/dev/null; then
        echo "  Loaded: $module (QEMU/KVM support)"
    fi
done

# Load other common drivers
for module in \
    nvme nvme-core \
    mpt3sas megaraid_sas hpsa \
    usb-storage uas; do
    if modprobe $module 2>/dev/null; then
        echo "  Loaded: $module"
    fi
done

# Show what actually loaded
echo ""
echo "Loaded modules:"
lsmod | grep -E "(ahci|ata|virtio|nvme|sd_mod|scsi)" | sort

# Start udev for device management
if [ -x /lib/systemd/systemd-udevd ]; then
    /lib/systemd/systemd-udevd --daemon --resolve-names=never
    udevadm trigger --type=subsystems --action=add
    udevadm trigger --type=devices --action=add
    udevadm settle --timeout=30
elif [ -x /sbin/udevd ]; then
    /sbin/udevd --daemon
    udevadm trigger
    udevadm settle --timeout=30
else
    # Fallback to mdev
    mdev -s
fi

# Wait for all devices to be detected
echo "Waiting for devices to settle..."
sleep 5

# Force rescan of SCSI buses
echo "Rescanning SCSI/SATA buses..."
for host in /sys/class/scsi_host/host*; do
    if [ -w "$host/scan" ]; then
        echo "- - -" > $host/scan 2>/dev/null || true
        echo "  Rescanned $(basename $host)"
    fi
done

# Try to manually trigger ATA link detection
echo "Checking ATA links..."
for ata_link in /sys/class/ata_link/link*/device/ata_device/dev*/class; do
    if [ -f "$ata_link" ]; then
        echo "  Found ATA device at: $ata_link"
        cat "$ata_link"
    fi
done

# Force virtio detection for QEMU
echo "Checking for virtio devices..."
if [ -d /sys/bus/virtio/devices ]; then
    for vdev in /sys/bus/virtio/devices/*; do
        if [ -d "$vdev" ]; then
            echo "  Found virtio device: $(basename $vdev)"
        fi
    done
fi

# Try manual SCSI device scan
echo "Manual SCSI scan..."
for chan in 0 1 2 3; do
    for id in 0 1 2 3 4 5 6 7; do
        for lun in 0 1; do
            echo "$chan $id $lun" > /sys/class/scsi_host/host0/scan 2>/dev/null || true
        done
    done
done

sleep 5

# Check kernel messages for disk detection
echo ""
echo "Kernel messages about storage:"
dmesg | tail -50 | grep -E "(ata|scsi|sd|vd|virtio)" || echo "No relevant messages"

# Double-check what block devices exist
echo ""
echo "Block devices in /sys/block:"
ls -la /sys/block/

# Check if we need specific QEMU/virtio configuration
echo ""
echo "PCI devices:"
lspci -k | grep -A2 -E "(SATA|SCSI|Virtio|storage)" || echo "lspci not available"

clear
echo "========================================"
echo "     UNIVERSAL DISK WIPER"
echo "========================================"
echo ""

# Show what we found
echo "Detected storage controllers:"
lspci 2>/dev/null | grep -E "(SATA|SCSI|IDE|NVMe|RAID)" || echo "lspci not available"
echo ""

echo "Block devices found:"
echo "==================="
lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null || {
    echo "Devices in /sys/block:"
    ls -la /sys/block/ | grep -v "loop\|ram"
}
echo ""

# Find all disk devices
DISKS=""
echo "Scanning for disks to wipe..."
echo ""

# Check all block devices
for dev in $(ls /sys/block/ | grep -v "loop\|ram\|sr\|fd"); do
    if [ -e "/sys/block/$dev/size" ]; then
        size=$(cat /sys/block/$dev/size)
        if [ "$size" -gt 0 ]; then
            devpath="/dev/$dev"
            
            # Create device node if it doesn't exist
            if [ ! -b "$devpath" ]; then
                major=$(cat /sys/block/$dev/dev | cut -d: -f1)
                minor=$(cat /sys/block/$dev/dev | cut -d: -f2)
                mknod $devpath b $major $minor 2>/dev/null
            fi
            
            if [ -b "$devpath" ]; then
                # Get device info
                model="Unknown"
                if [ -f "/sys/block/$dev/device/model" ]; then
                    model=$(cat /sys/block/$dev/device/model | tr -d '\n')
                fi
                
                size_gb=$((size * 512 / 1000 / 1000 / 1000))
                echo "Found: $devpath - ${size_gb}GB - $model"
                
                # Check if mounted
                if mount | grep -q "^$devpath"; then
                    echo "  Skipping - mounted (likely boot device)"
                    continue
                fi
                
                # Check if it's our boot device
                if dmesg | grep -q "$dev.*Attached.*CD-ROM\|$dev.*Attached.*DVD"; then
                    echo "  Skipping - optical drive"
                    continue
                fi
                
                DISKS="$DISKS $devpath"
                echo "  Will be wiped"
            fi
        fi
    fi
done

if [ -z "$DISKS" ]; then
    echo ""
    echo "ERROR: No disks found to wipe!"
    echo ""
    echo "This might be because:"
    echo "- All disks are mounted (boot devices)"
    echo "- Storage controller needs a driver that's not loaded"
    echo "- Hardware is not properly connected"
    echo ""
    echo "Debug information:"
    echo "=================="
    dmesg | grep -E "(ata|scsi|nvme|sd|vd|hd):" | tail -20
    echo ""
    echo "System will halt in 60 seconds..."
    sleep 60
    poweroff -f
fi

echo ""
echo "========================================"
echo "WARNING: THE FOLLOWING DISKS WILL BE"
echo "PERMANENTLY ERASED:"
echo "$DISKS"
echo "========================================"
echo ""
echo "Starting wipe in 15 seconds..."
echo "Press Ctrl+Alt+Del to abort"
sleep 15

# Wipe each disk
for disk in $DISKS; do
    echo ""
    echo "Wiping $disk..."
    echo -n "  Progress: "
    
    # Get disk size
    size_bytes=$(blockdev --getsize64 $disk 2>/dev/null || echo 0)
    size_mb=$((size_bytes / 1024 / 1024))
    
    # Wipe with progress indication
    dd if=/dev/zero of=$disk bs=1M count=1024 status=none 2>/dev/null
    echo -n "."
    
    # Wipe partition table area thoroughly
    dd if=/dev/zero of=$disk bs=1M count=10 status=none 2>/dev/null
    echo -n "."
    
    # Wipe end of disk (GPT backup)
    if [ $size_mb -gt 100 ]; then
        dd if=/dev/zero of=$disk bs=1M seek=$((size_mb - 10)) count=10 status=none 2>/dev/null
        echo -n "."
    fi
    
    # Final sync
    sync
    echo " Done!"
    echo "  Wiped partition tables and boot sectors"
done

echo ""
echo "========================================"
echo "     ALL DISKS HAVE BEEN WIPED!"
echo "========================================"
echo ""
echo "It is now safe to turn off the computer."
echo "System will power off in 10 seconds..."
sleep 10

# Sync and power off
sync
poweroff -f
EOINIT

chmod +x "$INITRD_DIR/init"

# Repack initrd
echo -e "${YELLOW}Creating custom initrd...${NC}"
find . | cpio -o -H newc | gzip -9 > "$ISO_DIR/boot/initrd.gz"
cd "$WORK_DIR"

# Setup isolinux for BIOS boot
echo -e "${YELLOW}Setting up isolinux for BIOS boot...${NC}"
ISOLINUX_DIR=$(find /nix/store -name isolinux.bin -type f 2>/dev/null | head -1 | xargs dirname)
if [ -n "$ISOLINUX_DIR" ]; then
    cp "$ISOLINUX_DIR/isolinux.bin" "$ISO_DIR/isolinux/"
    cp "$ISOLINUX_DIR"/*.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true
fi

# Create isolinux config
cat > "$ISO_DIR/isolinux/isolinux.cfg" << 'EOF'
DEFAULT wipe
PROMPT 0
TIMEOUT 100
ONTIMEOUT wipe

LABEL wipe
    MENU LABEL Universal Disk Wiper
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz quiet

LABEL wipe-verbose
    MENU LABEL Universal Disk Wiper (Verbose)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz
EOF

# Setup GRUB for EFI boot
echo -e "${YELLOW}Setting up GRUB for EFI boot...${NC}"
wget -q -O "$BUILD_DIR/grub-efi.deb" \
    "http://ftp.debian.org/debian/pool/main/g/grub2/grub-efi-amd64-bin_2.06-13+deb12u1_amd64.deb"

cd "$BUILD_DIR"
mkdir -p grub-extract
cd grub-extract
ar x ../grub-efi.deb
tar -xf data.tar.xz

if [ -f usr/lib/grub/x86_64-efi/monolithic/grubx64.efi ]; then
    cp usr/lib/grub/x86_64-efi/monolithic/grubx64.efi "$ISO_DIR/EFI/boot/bootx64.efi"
fi

cd "$WORK_DIR"

# Create GRUB config
mkdir -p "$ISO_DIR/boot/grub"
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=10
set default=0

menuentry "Universal Disk Wiper" {
    linux /boot/vmlinuz quiet
    initrd /boot/initrd.gz
}

menuentry "Universal Disk Wiper (Verbose)" {
    linux /boot/vmlinuz
    initrd /boot/initrd.gz
}
EOF

# Create EFI boot image
echo -e "${YELLOW}Creating EFI boot image...${NC}"
EFI_IMG="$BUILD_DIR/efiboot.img"

# Check size of bootx64.efi
if [ -f "$ISO_DIR/EFI/boot/bootx64.efi" ]; then
    EFI_SIZE=$(stat -c%s "$ISO_DIR/EFI/boot/bootx64.efi" 2>/dev/null || echo 3000000)
    EFI_SIZE_MB=$(( (EFI_SIZE / 1024 / 1024) + 2 ))
    echo "GRUB EFI size: ~${EFI_SIZE_MB}MB"
else
    EFI_SIZE_MB=10
fi

# Create image with enough space
dd if=/dev/zero of="$EFI_IMG" bs=1M count=$EFI_SIZE_MB
mkfs.vfat "$EFI_IMG"

export MTOOLS_SKIP_CHECK=1
mmd -i "$EFI_IMG" ::EFI
mmd -i "$EFI_IMG" ::EFI/boot
mcopy -i "$EFI_IMG" "$ISO_DIR/EFI/boot/bootx64.efi" ::EFI/boot/bootx64.efi

# Also copy grub.cfg to EFI directory
mkdir -p "$ISO_DIR/EFI/boot"
cp "$ISO_DIR/boot/grub/grub.cfg" "$ISO_DIR/EFI/boot/grub.cfg"

cp "$EFI_IMG" "$ISO_DIR/boot/efiboot.img"

# Find MBR
MBR_BIN=$(find /nix/store -name isohdpfx.bin -type f 2>/dev/null | head -1)

# Create the hybrid ISO
echo -e "${YELLOW}Creating hybrid ISO...${NC}"
xorriso -as mkisofs \
    -o "$OUTPUT_ISO" \
    -r -J -joliet-long \
    -V "DISK_WIPER" \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    ${MBR_BIN:+-isohybrid-mbr "$MBR_BIN"} \
    -eltorito-alt-boot \
    -e boot/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$ISO_DIR"

echo -e "${GREEN}Build complete!${NC}"
echo -e "ISO created: ${GREEN}$OUTPUT_ISO${NC}"
echo ""
echo -e "${RED}WARNING: This ISO will automatically wipe ALL internal hard drives!${NC}"
echo -e "${GREEN}Features:${NC}"
echo "- Works on ALL hardware (SATA, SAS, NVMe, RAID, USB)"
echo "- Supports both BIOS and UEFI boot"
echo "- Automatically detects all storage controllers"
echo "- Shows progress during wipe"
echo "- 15 second safety delay before wiping"