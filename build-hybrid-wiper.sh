#!/bin/bash
# Hybrid BIOS/UEFI Disk Wiper using isolinux and GRUB
# Simplified approach for maximum compatibility

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

echo -e "${GREEN}Hybrid Disk Wiper ISO Builder${NC}"
echo "==============================="

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Create directory structure
echo -e "${YELLOW}Creating build directories...${NC}"
mkdir -p "$ISO_DIR"/{isolinux,EFI/boot,boot}
mkdir -p "$INITRD_DIR"

# Download Debian kernel and initrd
echo -e "${YELLOW}Downloading Debian kernel and initrd...${NC}"
DEBIAN_MIRROR="http://ftp.debian.org/debian/dists/stable/main/installer-amd64/current/images"

wget -q -O "$ISO_DIR/boot/vmlinuz" "$DEBIAN_MIRROR/netboot/debian-installer/amd64/linux" || {
    echo -e "${RED}Failed to download kernel${NC}"
    exit 1
}

wget -q -O "$BUILD_DIR/initrd.gz" "$DEBIAN_MIRROR/netboot/debian-installer/amd64/initrd.gz" || {
    echo -e "${RED}Failed to download initrd${NC}"
    exit 1
}

# Extract and modify initrd
echo -e "${YELLOW}Customizing initrd...${NC}"
cd "$INITRD_DIR"
gzip -dc "$BUILD_DIR/initrd.gz" | cpio -id --quiet 2>/dev/null || true

# Check what we extracted
echo "Checking extracted initrd contents..."
if [ -d lib/modules ]; then
    echo "  Found kernel modules"
    KVER=$(ls lib/modules | head -1)
    echo "  Kernel version: $KVER"
    # List some important modules
    find lib/modules -name "*virtio*.ko" -o -name "*ata*.ko" -o -name "sd_mod.ko" | head -10
else
    echo "  WARNING: No kernel modules found in initrd!"
fi

# Preserve the original init as init.orig
if [ -f init ]; then
    mv init init.orig
fi

# Create simple init that wipes disks
cat > "$INITRD_DIR/init" << 'EOINIT'
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /run

# Suppress kernel messages
echo "1" > /proc/sys/kernel/printk

# Basic setup
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Load modules
echo "Loading kernel modules..."
for mod in sd_mod sr_mod ahci libahci libata ata_piix ata_generic virtio virtio_pci virtio_blk virtio_scsi virtio_ring; do
    if modprobe $mod 2>/dev/null; then
        echo "  Loaded: $mod"
    else
        echo "  Failed: $mod"
    fi
done

# Show loaded modules
echo ""
echo "Loaded modules:"
lsmod | grep -E "(virtio|ata|ahci|sd_mod)" || echo "No relevant modules loaded"
echo ""

# Check if modules directory exists
echo "Checking for kernel modules..."
if [ -d /lib/modules ]; then
    KVER=$(ls /lib/modules | head -1)
    echo "Kernel version: $KVER"
    if [ -d "/lib/modules/$KVER" ]; then
        echo "Module directory exists"
        # Run depmod to ensure module dependencies are set up
        if command -v depmod >/dev/null 2>&1; then
            echo "Running depmod..."
            depmod -a $KVER 2>/dev/null || echo "  depmod failed"
        fi
        # Check for virtio modules specifically
        echo "Looking for virtio modules:"
        find /lib/modules/$KVER -name "*virtio*" -type f | head -5
    else
        echo "ERROR: No modules for kernel $KVER"
    fi
else
    echo "ERROR: No /lib/modules directory - kernel modules missing!"
fi
echo ""

# Start udev
if [ -x /lib/systemd/systemd-udevd ]; then
    /lib/systemd/systemd-udevd --daemon
elif [ -x /sbin/udevd ]; then
    /sbin/udevd --daemon
else
    echo "udev not found, using mdev"
    mdev -s
fi

udevadm trigger 2>/dev/null || true
udevadm settle 2>/dev/null || true

# Force device node creation
echo "Creating device nodes..."
for major in 8 3 253 259; do
    for minor in 0 1 2 3 16 17 18 19 32 33 34 35; do
        case $major in
            8)  # SCSI disks
                dev="/dev/sd$(printf \\$(printf '%03o' $((97 + minor / 16))))$((minor % 16))"
                [ $((minor % 16)) -eq 0 ] && mknod ${dev%0} b $major $minor 2>/dev/null
                ;;
            3)  # IDE disks  
                dev="/dev/hd$(printf \\$(printf '%03o' $((97 + minor / 64))))"
                [ $((minor % 64)) -eq 0 ] && mknod $dev b $major $minor 2>/dev/null
                ;;
            253) # Virtio disks
                dev="/dev/vd$(printf \\$(printf '%03o' $((97 + minor))))"
                [ $minor -lt 26 ] && mknod $dev b $major $minor 2>/dev/null
                ;;
            259) # NVMe disks
                dev="/dev/nvme${minor}n1"
                [ $minor -lt 4 ] && mknod $dev b $major $minor 2>/dev/null
                ;;
        esac
    done
done

# Also create simpler device nodes
for letter in a b c d; do
    mknod /dev/sd${letter} b 8 $((0 + $(printf '%d' "'$letter") - 97)) 2>/dev/null || true
    mknod /dev/vd${letter} b 253 $((0 + $(printf '%d' "'$letter") - 97)) 2>/dev/null || true
    mknod /dev/hd${letter} b 3 $((0 + $(printf '%d' "'$letter") - 97)) 2>/dev/null || true
done

# Wait for devices
sleep 5

# Clear screen
clear

echo "========================================"
echo "     DISK WIPER - STARTING"
echo "========================================"
echo ""

# Show all block devices
echo "Block devices in /sys/block:"
echo "============================"
ls -la /sys/block/
echo ""

echo "Device nodes in /dev:"
echo "===================="
ls -la /dev/ | grep -E "^b.*[svhn]d" || echo "No block device nodes found"
echo ""

echo "Trying lsblk:"
echo "============="
if command -v lsblk >/dev/null 2>&1; then
    lsblk -a
else
    echo "lsblk not available"
fi
echo ""

# Find disks
DISKS=""
echo "Scanning for disks to wipe..."

# First check what's in /sys/block
echo "Checking /sys/block for devices..."
for sysdev in /sys/block/*; do
    if [ ! -e "$sysdev" ]; then
        continue
    fi
    
    devname=$(basename "$sysdev")
    
    # Skip loop, ram, and sr devices
    case "$devname" in
        loop*|ram*|sr*) 
            echo "  Skipping $devname (excluded type)"
            continue 
            ;;
    esac
    
    echo "  Found block device: $devname"
    
    # Check if device node exists
    if [ ! -b "/dev/$devname" ]; then
        echo "    Creating /dev/$devname"
        # Get major:minor
        if [ -f "$sysdev/dev" ]; then
            major_minor=$(cat "$sysdev/dev")
            major=${major_minor%:*}
            minor=${major_minor#*:}
            mknod "/dev/$devname" b $major $minor 2>/dev/null || echo "    Failed to create node"
        fi
    fi
    
    # Check the device
    if [ -b "/dev/$devname" ]; then
        echo "    Device node exists"
        
        # Skip if mounted
        if mount | grep -q "^/dev/$devname"; then
            echo "    Skipping: mounted"
            continue
        fi
        
        # Check if readable
        if dd if="/dev/$devname" of=/dev/null bs=512 count=1 2>/dev/null; then
            DISKS="$DISKS /dev/$devname"
            echo "    Added to wipe list"
        else
            echo "    Cannot read device"
        fi
    fi
done


if [ -z "$DISKS" ]; then
    echo ""
    echo "ERROR: No disks found to wipe!"
    echo ""
    echo "Debug: Kernel messages about disks:"
    dmesg | grep -E "(sd|vd|hd|nvme|virtio)" | tail -20
    echo ""
    echo "System will halt in 60 seconds..."
    sleep 60
    poweroff -f
fi

echo ""
echo "Will wipe:$DISKS"
echo ""
echo "Starting in 10 seconds... Press Ctrl+C to cancel"
sleep 10

# Wipe disks
for disk in $DISKS; do
    echo ""
    echo "Wiping $disk..."
    dd if=/dev/zero of="$disk" bs=1M count=100 2>&1 | grep -v records
    sync
    echo "Done with $disk"
done

echo ""
echo "========================================"
echo "     ALL DISKS HAVE BEEN WIPED!"
echo "========================================"
echo ""
echo "Powering off in 10 seconds..."
sleep 10

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
else
    echo -e "${RED}Warning: isolinux not found in nix store${NC}"
fi

# Create isolinux config
cat > "$ISO_DIR/isolinux/isolinux.cfg" << 'EOF'
DEFAULT wiper
PROMPT 0
TIMEOUT 50
ONTIMEOUT wiper

LABEL wiper
    MENU LABEL Disk Wiper
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz quiet

LABEL wiper-debug
    MENU LABEL Disk Wiper (Debug)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz
EOF

# Setup GRUB for EFI boot
echo -e "${YELLOW}Setting up GRUB for EFI boot...${NC}"

# Download Debian's GRUB EFI packages
wget -q -O "$BUILD_DIR/grub-efi.deb" \
    "http://ftp.debian.org/debian/pool/main/g/grub2/grub-efi-amd64-bin_2.06-13+deb12u1_amd64.deb"

cd "$BUILD_DIR"
mkdir -p grub-extract
cd grub-extract
ar x ../grub-efi.deb
tar -xf data.tar.xz

# Copy GRUB EFI binary
if [ -f usr/lib/grub/x86_64-efi/monolithic/grubx64.efi ]; then
    cp usr/lib/grub/x86_64-efi/monolithic/grubx64.efi "$ISO_DIR/EFI/boot/bootx64.efi"
else
    echo -e "${RED}Error: Could not find GRUB EFI binary${NC}"
    exit 1
fi

cd "$WORK_DIR"

# Create GRUB configuration in multiple locations for better compatibility
mkdir -p "$ISO_DIR/boot/grub"
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "Disk Wiper" {
    linux /boot/vmlinuz quiet
    initrd /boot/initrd.gz
}

menuentry "Disk Wiper (Debug)" {
    linux /boot/vmlinuz
    initrd /boot/initrd.gz
}
EOF

# Also put grub.cfg in EFI directory
mkdir -p "$ISO_DIR/EFI/boot"
cp "$ISO_DIR/boot/grub/grub.cfg" "$ISO_DIR/EFI/boot/grub.cfg"

# Create an EFI boot image
echo -e "${YELLOW}Creating EFI boot image...${NC}"
EFI_IMG="$BUILD_DIR/efiboot.img"

# Get sizes of files
KERNEL_SIZE=$(stat -c%s "$ISO_DIR/boot/vmlinuz" 2>/dev/null || echo 10000000)
INITRD_SIZE=$(stat -c%s "$ISO_DIR/boot/initrd.gz" 2>/dev/null || echo 20000000)
GRUB_SIZE=$(stat -c%s "$ISO_DIR/EFI/boot/bootx64.efi" 2>/dev/null || echo 2000000)

# Calculate needed size (files + overhead)
NEEDED_SIZE=$((($KERNEL_SIZE + $INITRD_SIZE + $GRUB_SIZE + 5000000) / 1024 / 1024 + 1))
echo "Creating ${NEEDED_SIZE}MB EFI image..."

# Create FAT image for EFI
dd if=/dev/zero of="$EFI_IMG" bs=1M count=$NEEDED_SIZE
mkfs.vfat -F 32 "$EFI_IMG"

# Mount and populate the EFI image
EFI_MNT="$BUILD_DIR/efi_mount"
mkdir -p "$EFI_MNT"

# Use mtools if mount fails (non-root)
if mount -o loop "$EFI_IMG" "$EFI_MNT" 2>/dev/null; then
    # Copy files to EFI image
    mkdir -p "$EFI_MNT/EFI/boot"
    cp "$ISO_DIR/EFI/boot/bootx64.efi" "$EFI_MNT/EFI/boot/"
    cp "$ISO_DIR/EFI/boot/grub.cfg" "$EFI_MNT/EFI/boot/"
    
    # Copy kernel and initrd to EFI image root
    cp "$ISO_DIR/boot/vmlinuz" "$EFI_MNT/"
    cp "$ISO_DIR/boot/initrd.gz" "$EFI_MNT/"
    
    umount "$EFI_MNT"
else
    echo "Using mtools to populate EFI image..."
    export MTOOLS_SKIP_CHECK=1
    
    # Create directories
    mmd -i "$EFI_IMG" ::EFI 2>/dev/null || true
    mmd -i "$EFI_IMG" ::EFI/boot 2>/dev/null || true
    
    # Copy files (note: mtools needs :: prefix for destination)
    mcopy -i "$EFI_IMG" "$ISO_DIR/EFI/boot/bootx64.efi" ::EFI/boot/bootx64.efi
    mcopy -i "$EFI_IMG" "$ISO_DIR/EFI/boot/grub.cfg" ::EFI/boot/grub.cfg
    mcopy -i "$EFI_IMG" "$ISO_DIR/boot/vmlinuz" ::vmlinuz
    mcopy -i "$EFI_IMG" "$ISO_DIR/boot/initrd.gz" ::initrd.gz
fi

rmdir "$EFI_MNT" 2>/dev/null || true

# Find MBR binary
MBR_BIN=$(find /nix/store -name isohdpfx.bin -type f 2>/dev/null | head -1)

# Copy the EFI boot image to ISO
cp "$EFI_IMG" "$ISO_DIR/boot/efiboot.img"

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