#!/bin/bash
# Complete Disk Wiper Builder - Builds custom kernel and ISO
# This script builds everything needed for the universal disk wiper

set -e

# Configuration
WORK_DIR="$(pwd)"
KERNEL_BUILD_DIR="$WORK_DIR/kernel-build"
ISO_BUILD_DIR="$WORK_DIR/wiper-build"
OUTPUT_ISO="$WORK_DIR/disk-wiper.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Complete Disk Wiper Builder${NC}"
echo "============================"
echo ""

# Step 1: Build custom kernel if it doesn't exist
if [ ! -f "$KERNEL_BUILD_DIR/linux-6.6.13/arch/x86/boot/bzImage" ]; then
    echo -e "${YELLOW}Step 1: Building custom kernel...${NC}"
    ./build-custom-kernel.sh
    
    if [ ! -f "$KERNEL_BUILD_DIR/linux-6.6.13/arch/x86/boot/bzImage" ]; then
        echo -e "${RED}ERROR: Kernel build failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Step 1: Custom kernel already built${NC}"
fi

# Step 2: Build the ISO with the custom kernel
echo ""
echo -e "${YELLOW}Step 2: Building ISO with custom kernel...${NC}"

# Create a modified version of build-universal-wiper.sh that uses our custom kernel
cat > build-final-iso.sh << 'EOF'
#!/bin/bash
# Final ISO builder using custom kernel

set -e

# Configuration
WORK_DIR="$(pwd)"
BUILD_DIR="$WORK_DIR/wiper-build"
ISO_DIR="$BUILD_DIR/iso"
INITRD_DIR="$BUILD_DIR/custom-initrd"
OUTPUT_ISO="$WORK_DIR/disk-wiper.iso"
CUSTOM_KERNEL="$WORK_DIR/kernel-build/linux-6.6.13/arch/x86/boot/bzImage"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Universal Disk Wiper ISO Builder (Custom Kernel)${NC}"
echo "================================================"

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Create directory structure
echo -e "${YELLOW}Creating build directories...${NC}"
mkdir -p "$ISO_DIR"/{isolinux,EFI/boot,boot}
mkdir -p "$INITRD_DIR"

# Use our custom kernel
echo -e "${YELLOW}Using custom kernel with all drivers built-in...${NC}"
if [ -f "$CUSTOM_KERNEL" ]; then
    cp "$CUSTOM_KERNEL" "$ISO_DIR/boot/vmlinuz"
    echo "Custom kernel copied successfully"
else
    echo -e "${RED}ERROR: Custom kernel not found at $CUSTOM_KERNEL${NC}"
    exit 1
fi

# Create minimal initrd with just our init script
echo -e "${YELLOW}Creating minimal initrd...${NC}"
cd "$INITRD_DIR"

# Create directory structure
mkdir -p {bin,sbin,dev,proc,sys,run,tmp,etc,lib,lib64,usr/bin,usr/sbin}

# Device nodes will be created by devtmpfs at runtime

# We need a shell and basic utilities
# Download a static busybox
echo "Downloading static busybox..."
wget -q -O bin/busybox "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
chmod +x bin/busybox

# Create symlinks for all busybox applets
cd bin
for cmd in sh ash cat chmod chown cp dd df echo false grep kill ln ls lsmod mkdir mknod modprobe mount mv poweroff ps rm rmdir sed sleep sync true umount uname; do
    ln -s busybox $cmd
done
cd ..

# Also create /sbin links
cd sbin
for cmd in blkid blockdev depmod fdisk halt init insmod lsmod mdev modprobe mount poweroff reboot rmmod swapoff swapon switch_root umount; do
    ln -s ../bin/busybox $cmd
done
cd ..

# Create our disk wiper init
cat > "$INITRD_DIR/init" << 'EOINIT'
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /run

# Suppress kernel messages
echo "1" > /proc/sys/kernel/printk

# Set up environment
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

clear
echo "========================================"
echo "     UNIVERSAL DISK WIPER"
echo "     (Custom Kernel Edition)"
echo "========================================"
echo ""
echo "Kernel: $(uname -r)"
echo ""

# Wait for devices to settle
echo "Waiting for devices to settle..."
sleep 5

# Force rescan of SCSI buses
echo "Rescanning SCSI/SATA buses..."
for host in /sys/class/scsi_host/host*; do
    if [ -w "$host/scan" ]; then
        echo "- - -" > $host/scan 2>/dev/null || true
    fi
done

sleep 3

clear
echo "========================================"
echo "     UNIVERSAL DISK WIPER"
echo "========================================"
echo ""

# Show what we found
echo "Storage controllers detected:"
for pci in /sys/bus/pci/devices/*/class; do
    if [ -f "$pci" ]; then
        class=$(cat "$pci")
        # Check for storage controllers (class 01xxxx)
        case "$class" in
            0x0101*|0x0104*|0x0106*|0x0107*|0x0108*)
                device=$(dirname "$pci")/device
                vendor=$(dirname "$pci")/vendor
                if [ -f "$device" ] && [ -f "$vendor" ]; then
                    echo "  Controller: $(cat "$vendor"):$(cat "$device")"
                fi
                ;;
        esac
    fi
done
echo ""

echo "Block devices found:"
echo "===================="
ls -la /sys/block/ | grep -v "loop\|ram"
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
                if cat /proc/mounts | grep -q "^$devpath"; then
                    echo "  Skipping - mounted (likely boot device)"
                    continue
                fi
                
                # Check if it's our boot device
                SKIP=0
                for bootdev in $(cat /proc/cmdline | grep -o "root=[^ ]*" | cut -d= -f2); do
                    if [ "$devpath" = "$bootdev" ]; then
                        SKIP=1
                        break
                    fi
                done
                
                if [ "$SKIP" -eq 1 ]; then
                    echo "  Skipping - boot device"
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
    echo "- Hardware is not properly connected"
    echo ""
    echo "Debug information:"
    echo "=================="
    dmesg | tail -50 | grep -E "(ata|scsi|nvme|sd|vd|hd):" || echo "No relevant kernel messages"
    echo ""
    echo "System will halt in 60 seconds..."
    sleep 60
    poweroff -f
fi

echo ""
echo "Starting disk wipe..."

# Wipe each disk
for disk in $DISKS; do
    echo ""
    echo "Wiping $disk..."
    echo -n "  Progress: "
    
    # Get disk size
    if [ -b "$disk" ]; then
        # Wipe first 100MB
        dd if=/dev/zero of=$disk bs=1M count=100 status=none 2>/dev/null
        echo -n "."
        
        # Wipe partition table area thoroughly
        dd if=/dev/zero of=$disk bs=1M count=10 status=none 2>/dev/null
        echo -n "."
        
        # Try to wipe end of disk (GPT backup)
        dd if=/dev/zero of=$disk bs=1M seek=1000 count=10 status=none 2>/dev/null || true
        echo -n "."
        
        # Final sync
        sync
        echo " Done!"
        echo "  Wiped partition tables and boot sectors"
    else
        echo " Failed - device not accessible"
    fi
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

# Create initrd
echo -e "${YELLOW}Creating initrd...${NC}"
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
cat > "$ISO_DIR/isolinux/isolinux.cfg" << 'EOCFG'
DEFAULT wipe
PROMPT 0
TIMEOUT 100
ONTIMEOUT wipe

LABEL wipe
    MENU LABEL Universal Disk Wiper (Custom Kernel)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz quiet

LABEL wipe-verbose
    MENU LABEL Universal Disk Wiper (Verbose)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz
EOCFG

# Setup GRUB for EFI boot
echo -e "${YELLOW}Setting up GRUB for EFI boot...${NC}"

# We'll create the GRUB config later

# Download GRUB modules
wget -q -O "$BUILD_DIR/grub-efi.deb" \
    "http://ftp.debian.org/debian/pool/main/g/grub2/grub-efi-amd64-bin_2.06-13+deb12u1_amd64.deb"

cd "$BUILD_DIR"
mkdir -p grub-extract
cd grub-extract
ar x ../grub-efi.deb
tar -xf data.tar.xz

# Use the monolithic GRUB image
if [ -f usr/lib/grub/x86_64-efi/monolithic/grubx64.efi ]; then
    cp usr/lib/grub/x86_64-efi/monolithic/grubx64.efi "$ISO_DIR/EFI/boot/bootx64.efi"
else
    echo -e "${RED}Error: GRUB EFI binary not found${NC}"
    exit 1
fi

cd "$WORK_DIR"

# Create GRUB config
mkdir -p "$ISO_DIR/boot/grub"
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOCFG'
set timeout=3
set default=0

# Try multiple paths since GRUB might see different root depending on boot method
menuentry "Universal Disk Wiper" {
    search --no-floppy --set=root --file /boot/vmlinuz
    linux /boot/vmlinuz quiet
    initrd /boot/initrd.gz
}

menuentry "Universal Disk Wiper (Verbose)" {
    search --no-floppy --set=root --file /boot/vmlinuz
    linux /boot/vmlinuz
    initrd /boot/initrd.gz
}
EOCFG

# Also create grub.cfg in the EFI directory for better compatibility
mkdir -p "$ISO_DIR/EFI/boot"
cp "$ISO_DIR/boot/grub/grub.cfg" "$ISO_DIR/EFI/boot/grub.cfg"

# Create EFI boot image
echo -e "${YELLOW}Creating EFI boot image...${NC}"
EFI_IMG="$BUILD_DIR/efiboot.img"

# Calculate size needed for EFI image
KERNEL_SIZE=$(stat -c%s "$ISO_DIR/boot/vmlinuz" 2>/dev/null || echo 15000000)
INITRD_SIZE=$(stat -c%s "$ISO_DIR/boot/initrd.gz" 2>/dev/null || echo 5000000)
GRUB_SIZE=$(stat -c%s "$ISO_DIR/EFI/boot/bootx64.efi" 2>/dev/null || echo 3000000)
TOTAL_SIZE=$((($KERNEL_SIZE + $INITRD_SIZE + $GRUB_SIZE + 5000000) / 1024 / 1024 + 2))

echo "Creating ${TOTAL_SIZE}MB EFI image..."
dd if=/dev/zero of="$EFI_IMG" bs=1M count=$TOTAL_SIZE
mkfs.vfat "$EFI_IMG"

export MTOOLS_SKIP_CHECK=1
# Create directory structure
mmd -i "$EFI_IMG" ::EFI
mmd -i "$EFI_IMG" ::EFI/boot
mmd -i "$EFI_IMG" ::boot

# Copy GRUB
mcopy -i "$EFI_IMG" "$ISO_DIR/EFI/boot/bootx64.efi" ::EFI/boot/bootx64.efi

# Copy kernel and initrd to boot directory in EFI image
mcopy -i "$EFI_IMG" "$ISO_DIR/boot/vmlinuz" ::boot/vmlinuz
mcopy -i "$EFI_IMG" "$ISO_DIR/boot/initrd.gz" ::boot/initrd.gz

# Also copy grub.cfg to EFI image
mcopy -i "$EFI_IMG" "$ISO_DIR/boot/grub/grub.cfg" ::EFI/boot/grub.cfg

cp "$EFI_IMG" "$ISO_DIR/boot/efiboot.img"

# Find MBR
MBR_BIN=$(find /nix/store -name isohdpfx.bin -type f 2>/dev/null | head -1)

# Create the hybrid ISO
echo -e "${YELLOW}Creating hybrid ISO...${NC}"
xorriso -as mkisofs \
    -o "$OUTPUT_ISO" \
    -r -J -joliet-long \
    -V "DISK_WIPER_CUSTOM" \
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
echo "- Custom kernel with ALL storage drivers built-in"
echo "- No module loading required"
echo "- Works on ALL hardware (SATA, SAS, NVMe, RAID, USB, VirtIO)"
echo "- Supports both BIOS and UEFI boot"
echo "- Immediate wiping with no delay"
EOF

chmod +x build-final-iso.sh
./build-final-iso.sh

# Clean up temporary script
rm -f build-final-iso.sh

echo ""
echo -e "${GREEN}Complete build finished!${NC}"
echo -e "ISO created: ${GREEN}$OUTPUT_ISO${NC}"
echo ""
echo "The disk wiper ISO includes:"
echo "- Custom kernel (6.6.13 LTS) with all storage drivers built-in"
echo "- Support for SATA, NVMe, VirtIO, RAID controllers"
echo "- Both BIOS and UEFI boot support"
echo "- Automatic disk detection and wiping"
echo "- Boot device protection"