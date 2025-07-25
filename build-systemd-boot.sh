#!/bin/bash
# Disk Wiper with systemd-boot for EFI and syslinux for BIOS

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

echo -e "${GREEN}Disk Wiper ISO Builder (systemd-boot)${NC}"
echo "======================================"

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
mkdir -p "$ISO_DIR"/{isolinux,boot,EFI/BOOT,loader/entries}
mkdir -p "$INITRD_DIR"

# Use custom kernel or download one
if [ -f "$CUSTOM_KERNEL" ]; then
    echo -e "${YELLOW}Using custom kernel...${NC}"
    cp "$CUSTOM_KERNEL" "$ISO_DIR/vmlinuz"
else
    echo -e "${YELLOW}Custom kernel not found, using Debian kernel...${NC}"
    wget --show-progress -O "$ISO_DIR/vmlinuz" \
        "http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
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

# Setup systemd-boot for EFI
echo -e "${YELLOW}Setting up systemd-boot for EFI...${NC}"

# Download systemd-boot if not already cached
if [ ! -f "$BUILD_DIR/systemd-boot.deb" ]; then
    SYSTEMD_URL="http://ftp.debian.org/debian/pool/main/s/systemd/systemd-boot-efi_254.26-1~bpo12+1_amd64.deb"
    echo "Downloading systemd-boot from: $SYSTEMD_URL"
    wget --show-progress -O "$BUILD_DIR/systemd-boot.deb" "$SYSTEMD_URL" || {
        echo -e "${RED}Failed to download systemd-boot${NC}"
        # Try alternative URL
        echo "Trying alternative URL..."
        SYSTEMD_URL="http://deb.debian.org/debian/pool/main/s/systemd/systemd-boot-efi_254.26-1~bpo12+1_amd64.deb"
        wget --show-progress -O "$BUILD_DIR/systemd-boot.deb" "$SYSTEMD_URL" || {
            echo -e "${RED}Failed to download systemd-boot from alternative URL${NC}"
            exit 1
        }
    }
else
    echo "Using cached systemd-boot..."
fi

cd "$BUILD_DIR"
rm -rf systemd-extract
mkdir -p systemd-extract
cd systemd-extract
ar x ../systemd-boot.deb
tar -xf data.tar.xz

# Copy systemd-boot EFI binary
if [ -f usr/lib/systemd/boot/efi/systemd-bootx64.efi ]; then
    cp usr/lib/systemd/boot/efi/systemd-bootx64.efi "$ISO_DIR/EFI/BOOT/BOOTX64.EFI"
else
    echo -e "${RED}systemd-boot not found!${NC}"
    exit 1
fi

cd "$WORK_DIR"

# Create loader config
cat > "$ISO_DIR/loader/loader.conf" << 'EOF'
default wiper
timeout 3
EOF

# Create boot entry
cat > "$ISO_DIR/loader/entries/wiper.conf" << 'EOF'
title   Universal Disk Wiper
linux   /vmlinuz
initrd  /initrd.gz
options quiet
EOF

# Create EFI boot image
echo -e "${YELLOW}Creating EFI boot image...${NC}"
EFI_IMG="$BUILD_DIR/efiboot.img"

# Calculate size
TOTAL_SIZE=20

dd if=/dev/zero of="$EFI_IMG" bs=1M count=$TOTAL_SIZE
mkfs.vfat -F 32 "$EFI_IMG"

# Populate EFI image
export MTOOLS_SKIP_CHECK=1
mmd -i "$EFI_IMG" ::EFI
mmd -i "$EFI_IMG" ::EFI/BOOT
mmd -i "$EFI_IMG" ::loader
mmd -i "$EFI_IMG" ::loader/entries

mcopy -i "$EFI_IMG" "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" ::EFI/BOOT/
mcopy -i "$EFI_IMG" "$ISO_DIR/vmlinuz" ::/
mcopy -i "$EFI_IMG" "$ISO_DIR/initrd.gz" ::/
mcopy -i "$EFI_IMG" "$ISO_DIR/loader/loader.conf" ::loader/
mcopy -i "$EFI_IMG" "$ISO_DIR/loader/entries/wiper.conf" ::loader/entries/

# Copy EFI image to ISO directory
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
echo "- systemd-boot for EFI (simpler than GRUB)"
echo "- syslinux for BIOS"
echo "- Immediate wiping with no delay"
echo "- Works with custom kernel or standard kernel"