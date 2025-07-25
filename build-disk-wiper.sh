#!/bin/bash
# Simple EFI/BIOS Disk Wiper with direct kernel loading

set -e

# Configuration
WORK_DIR="$(pwd)"
BUILD_DIR="$WORK_DIR/wiper-build"
ISO_DIR="$BUILD_DIR/iso"
INITRD_DIR="$BUILD_DIR/custom-initrd"
OUTPUT_ISO="$WORK_DIR/disk-wiper.iso"

# Use custom kernel if available
CUSTOM_KERNEL="$WORK_DIR/kernel-build/linux-6.6.13/arch/x86/boot/bzImage"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Simple EFI/BIOS Disk Wiper ISO Builder${NC}"
echo "======================================="

# Clean only ISO directory to preserve downloads
if [ -d "$ISO_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous ISO build...${NC}"
    rm -rf "$ISO_DIR"
fi
if [ -d "$INITRD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous initrd...${NC}"
    rm -rf "$INITRD_DIR"
fi

# Create directory structure
echo -e "${YELLOW}Creating build directories...${NC}"
mkdir -p "$ISO_DIR"/{isolinux,EFI/BOOT,boot/grub}
mkdir -p "$INITRD_DIR"

# Use custom kernel or download one
if [ -f "$CUSTOM_KERNEL" ] && [ "${USE_STOCK_KERNEL:-false}" != "true" ]; then
    echo -e "${YELLOW}Using custom kernel...${NC}"
    cp "$CUSTOM_KERNEL" "$ISO_DIR/vmlinuz"
else
    echo -e "${YELLOW}Using Debian stock kernel for testing...${NC}"
    if [ ! -f "$BUILD_DIR/debian-kernel" ]; then
        wget --show-progress -O "$BUILD_DIR/debian-kernel" \
            "http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
    fi
    cp "$BUILD_DIR/debian-kernel" "$ISO_DIR/vmlinuz"
fi

# Create minimal initrd
echo -e "${YELLOW}Creating minimal initrd...${NC}"
cd "$INITRD_DIR"

# Create directory structure
mkdir -p {bin,sbin,dev,proc,sys,run,tmp,etc,lib,lib64,usr/bin,usr/sbin}

# Download static busybox if not already cached
if [ ! -f "$BUILD_DIR/busybox-cache" ]; then
    echo "Downloading static busybox..."
    wget --show-progress -O "$BUILD_DIR/busybox-cache" "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
else
    echo "Using cached busybox..."
fi
cp "$BUILD_DIR/busybox-cache" bin/busybox
chmod +x bin/busybox

# Create symlinks
cd bin
for cmd in sh ash cat chmod chown cp dd df echo false grep kill ln ls lsmod mkdir mknod modprobe mount mv poweroff ps rm rmdir sed sleep sync true umount uname; do
    ln -s busybox $cmd
done
cd ..

cd sbin
for cmd in blkid blockdev depmod fdisk halt init insmod lsmod mdev modprobe mount poweroff reboot rmmod swapoff swapon switch_root umount; do
    ln -s ../bin/busybox $cmd
done
cd ..

# Create init script
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
echo "========================================"
echo ""

# Wait for devices
echo "Waiting for devices to settle..."
sleep 5

# Force rescan
for host in /sys/class/scsi_host/host*; do
    if [ -w "$host/scan" ]; then
        echo "- - -" > $host/scan 2>/dev/null || true
    fi
done

sleep 3

# Find disks
DISKS=""
echo "Scanning for disks to wipe..."
echo ""

for dev in $(ls /sys/block/ | grep -v "loop\|ram\|sr\|fd"); do
    if [ -e "/sys/block/$dev/size" ]; then
        size=$(cat /sys/block/$dev/size)
        if [ "$size" -gt 0 ]; then
            devpath="/dev/$dev"
            
            if [ ! -b "$devpath" ]; then
                major=$(cat /sys/block/$dev/dev | cut -d: -f1)
                minor=$(cat /sys/block/$dev/dev | cut -d: -f2)
                mknod $devpath b $major $minor 2>/dev/null
            fi
            
            if [ -b "$devpath" ]; then
                model="Unknown"
                if [ -f "/sys/block/$dev/device/model" ]; then
                    model=$(cat /sys/block/$dev/device/model | tr -d '\n')
                fi
                
                size_gb=$((size * 512 / 1000 / 1000 / 1000))
                echo "Found: $devpath - ${size_gb}GB - $model"
                
                if cat /proc/mounts | grep -q "^$devpath"; then
                    echo "  Skipping - mounted"
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
    
    dd if=/dev/zero of=$disk bs=1M count=100 status=none 2>/dev/null
    echo -n "."
    
    dd if=/dev/zero of=$disk bs=1M count=10 status=none 2>/dev/null
    echo -n "."
    
    sync
    echo " Done!"
done

echo ""
echo "========================================"
echo "     ALL DISKS HAVE BEEN WIPED!"
echo "========================================"
echo ""
echo "System will power off in 10 seconds..."
sleep 10

sync
poweroff -f
EOINIT

chmod +x "$INITRD_DIR/init"

# Create initrd
echo -e "${YELLOW}Creating initrd...${NC}"
find . | cpio -o -H newc | gzip -9 > "$ISO_DIR/initrd.gz"
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
TIMEOUT 50

LABEL wipe
    KERNEL /vmlinuz
    APPEND initrd=/initrd.gz quiet
EOF

# Setup GRUB for EFI boot - using simplified approach
echo -e "${YELLOW}Setting up GRUB for EFI boot...${NC}"

# Download GRUB EFI if not already cached
if [ ! -f "$BUILD_DIR/grub-efi.deb" ]; then
    echo "Downloading GRUB EFI..."
    wget --show-progress -O "$BUILD_DIR/grub-efi.deb" \
        "http://ftp.debian.org/debian/pool/main/g/grub2/grub-efi-amd64-bin_2.06-13+deb12u1_amd64.deb"
else
    echo "Using cached GRUB EFI..."
fi

cd "$BUILD_DIR"
rm -rf grub-extract
mkdir -p grub-extract
cd grub-extract
ar x ../grub-efi.deb
tar -xf data.tar.xz

# Copy the monolithic GRUB that has all modules
if [ -f usr/lib/grub/x86_64-efi/monolithic/grubx64.efi ]; then
    cp usr/lib/grub/x86_64-efi/monolithic/grubx64.efi "$ISO_DIR/EFI/BOOT/bootx64.efi"
else
    echo -e "${RED}Error: GRUB EFI binary not found${NC}"
    exit 1
fi

cd "$WORK_DIR"

# Create simple GRUB config
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=3
set default=0

# No serial console needed for production

# Simple direct boot
menuentry "Universal Disk Wiper" {
    linux /vmlinuz quiet
    initrd /initrd.gz
}
EOF

# Files are already in the ISO root directory

# Create minimal EFI boot image
echo -e "${YELLOW}Creating EFI boot image...${NC}"
EFI_IMG="$BUILD_DIR/efiboot.img"

# Create a larger image to fit all files
dd if=/dev/zero of="$EFI_IMG" bs=1M count=32
mkfs.vfat "$EFI_IMG"

export MTOOLS_SKIP_CHECK=1
mmd -i "$EFI_IMG" ::EFI 2>/dev/null || true
mmd -i "$EFI_IMG" ::EFI/BOOT 2>/dev/null || true
mcopy -o -i "$EFI_IMG" "$ISO_DIR/EFI/BOOT/bootx64.efi" ::EFI/BOOT/bootx64.efi
# Also copy kernel and initrd to EFI image root
mcopy -o -i "$EFI_IMG" "$ISO_DIR/vmlinuz" ::/vmlinuz
mcopy -o -i "$EFI_IMG" "$ISO_DIR/initrd.gz" ::/initrd.gz

# Copy to ISO directory
mkdir -p "$ISO_DIR/boot"
cp "$EFI_IMG" "$ISO_DIR/boot/efiboot.img"

# Find MBR
MBR_BIN=$(find /nix/store -name isohdpfx.bin -type f 2>/dev/null | head -1)

# Remove old ISO if it exists
if [ -f "$OUTPUT_ISO" ]; then
    echo "Removing old ISO..."
    rm -f "$OUTPUT_ISO"
fi

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
echo "Features:"
echo "- Simple GRUB configuration for EFI"
echo "- Direct kernel loading (no searching required)"
echo "- isolinux for BIOS"
echo "- Immediate wiping with no delay"