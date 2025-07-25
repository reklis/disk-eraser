#!/bin/bash
# Custom Kernel Builder for Universal Disk Wiper
# Builds a kernel with all storage drivers built-in

set -e

# Configuration
WORK_DIR="$(pwd)"
BUILD_DIR="$WORK_DIR/kernel-build"
KERNEL_VERSION="6.12.40"  # LTS kernel
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Custom Kernel Builder${NC}"
echo "======================"

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download kernel source
echo -e "${YELLOW}Downloading kernel ${KERNEL_VERSION}...${NC}"
wget --show-progress -O linux.tar.xz "$KERNEL_URL"

echo -e "${YELLOW}Extracting kernel source...${NC}"
tar -xf linux.tar.xz
cd "linux-${KERNEL_VERSION}"

# Create kernel configuration
echo -e "${YELLOW}Creating kernel configuration...${NC}"

# Start with a default config then customize it
make defconfig

# Now modify the config for our needs
cat >> .config << 'EOF'
# Custom settings for disk wiper
CONFIG_LOCALVERSION="-diskwiper"
CONFIG_LOCALVERSION_AUTO=n

# Disable modules - everything built-in
CONFIG_MODULES=n
CONFIG_MODULE_UNLOAD=n

# Early boot essentials
CONFIG_BLK_DEV_INITRD=y
CONFIG_INITRAMFS_SOURCE=""
CONFIG_RD_GZIP=y
CONFIG_INITRAMFS_COMPRESSION_GZIP=y

# Block layer
CONFIG_BLOCK=y
CONFIG_LBDAF=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_BSG=y

# Executable formats
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y

# Device Drivers
CONFIG_PCI=y
CONFIG_PCI_MSI=y

# SCSI support (built-in)
CONFIG_SCSI=y
CONFIG_SCSI_DMA=y
CONFIG_SCSI_PROC_FS=y
CONFIG_BLK_DEV_SD=y
CONFIG_BLK_DEV_SR=y
CONFIG_CHR_DEV_SG=y
CONFIG_SCSI_CONSTANTS=y
CONFIG_SCSI_SPI_ATTRS=y
CONFIG_SCSI_SAS_ATTRS=y
CONFIG_SCSI_SAS_LIBSAS=y

# SATA/PATA support (built-in)
CONFIG_ATA=y
CONFIG_ATA_VERBOSE_ERROR=y
CONFIG_ATA_ACPI=y
CONFIG_SATA_PMP=y
CONFIG_SATA_AHCI=y
CONFIG_SATA_AHCI_PLATFORM=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_PIIX=y
CONFIG_SATA_MV=y
CONFIG_SATA_NV=y
CONFIG_SATA_PROMISE=y
CONFIG_SATA_SIL=y
CONFIG_SATA_SIS=y
CONFIG_SATA_SVW=y
CONFIG_SATA_ULI=y
CONFIG_SATA_VIA=y
CONFIG_SATA_VITESSE=y
CONFIG_PATA_ALI=y
CONFIG_PATA_AMD=y
CONFIG_PATA_ARTOP=y
CONFIG_PATA_ATIIXP=y
CONFIG_PATA_ATP867X=y
CONFIG_PATA_CMD64X=y
CONFIG_PATA_EFAR=y
CONFIG_PATA_HPT366=y
CONFIG_PATA_HPT37X=y
CONFIG_PATA_HPT3X2N=y
CONFIG_PATA_HPT3X3=y
CONFIG_PATA_IT8213=y
CONFIG_PATA_IT821X=y
CONFIG_PATA_JMICRON=y
CONFIG_PATA_MARVELL=y
CONFIG_PATA_NETCELL=y
CONFIG_PATA_NINJA32=y
CONFIG_PATA_NS87415=y
CONFIG_PATA_OLDPIIX=y
CONFIG_PATA_PDC2027X=y
CONFIG_PATA_PDC_OLD=y
CONFIG_PATA_RDC=y
CONFIG_PATA_SCH=y
CONFIG_PATA_SERVERWORKS=y
CONFIG_PATA_SIL680=y
CONFIG_PATA_TOSHIBA=y
CONFIG_PATA_TRIFLEX=y
CONFIG_PATA_VIA=y
CONFIG_PATA_WINBOND=y
CONFIG_PATA_ACPI=y
CONFIG_ATA_GENERIC=y

# VirtIO support (built-in) - Critical for QEMU/KVM
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MENU=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_PCI_LEGACY=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_BLK_SCSI=y
CONFIG_SCSI_VIRTIO=y
CONFIG_VIRTIO_CONSOLE=y

# NVMe support (built-in)
CONFIG_NVME_CORE=y
CONFIG_BLK_DEV_NVME=y
CONFIG_NVME_MULTIPATH=y

# Common RAID controllers (built-in)
CONFIG_MEGARAID_NEWGEN=y
CONFIG_MEGARAID_MM=y
CONFIG_MEGARAID_MAILBOX=y
CONFIG_MEGARAID_LEGACY=y
CONFIG_MEGARAID_SAS=y
CONFIG_SCSI_AACRAID=y
CONFIG_SCSI_AIC7XXX=y
CONFIG_SCSI_AIC79XX=y
CONFIG_SCSI_AIC94XX=y
CONFIG_SCSI_MVSAS=y
CONFIG_SCSI_MVUMI=y
CONFIG_SCSI_ADVANSYS=y
CONFIG_SCSI_ARCMSR=y
CONFIG_SCSI_HPSA=y
CONFIG_SCSI_SMARTPQI=y
CONFIG_SCSI_3W_9XXX=y
CONFIG_SCSI_3W_SAS=y
CONFIG_SCSI_LPFC=y
CONFIG_SCSI_MPT3SAS=y
CONFIG_SCSI_MPT2SAS=y
CONFIG_SCSI_STEX=y

# USB storage (built-in)
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_ANNOUNCE_NEW_DEVICES=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_UHCI_HCD=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y

# Additional USB storage drivers for external drives
CONFIG_USB_STORAGE_REALTEK=y
CONFIG_USB_STORAGE_DATAFAB=y
CONFIG_USB_STORAGE_FREECOM=y
CONFIG_USB_STORAGE_ISD200=y
CONFIG_USB_STORAGE_USBAT=y
CONFIG_USB_STORAGE_SDDR09=y
CONFIG_USB_STORAGE_SDDR55=y
CONFIG_USB_STORAGE_JUMPSHOT=y
CONFIG_USB_STORAGE_ALAUDA=y
CONFIG_USB_STORAGE_ONETOUCH=y
CONFIG_USB_STORAGE_KARMA=y
CONFIG_USB_STORAGE_CYPRESS_ATACB=y
CONFIG_USB_STORAGE_ENE_UB6250=y

# Firewire/IEEE1394 support for external drives
CONFIG_FIREWIRE=y
CONFIG_FIREWIRE_OHCI=y
CONFIG_FIREWIRE_SBP2=y

# Thunderbolt support
CONFIG_THUNDERBOLT=y

# Filesystems (minimal)
CONFIG_EXT2_FS=y
CONFIG_EXT3_FS=y
CONFIG_EXT4_FS=y
CONFIG_VFAT_FS=y
CONFIG_FAT_DEFAULT_CODEPAGE=437
CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"
CONFIG_ISO9660_FS=y
CONFIG_JOLIET=y
CONFIG_PROC_FS=y
CONFIG_PROC_SYSCTL=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y

# Networking (minimal for PXE)
CONFIG_NET=y
CONFIG_PACKET=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y

# Console and TTY
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_CONSOLE_TRANSLATIONS=y
CONFIG_VT_CONSOLE=y
CONFIG_HW_CONSOLE=y
CONFIG_UNIX98_PTYS=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_PCI=y
CONFIG_SERIAL_8250_NR_UARTS=4
CONFIG_SERIAL_8250_RUNTIME_UARTS=4

# Framebuffer support (required for EFI console)
CONFIG_FB=y
CONFIG_FB_EFI=y
CONFIG_FB_VESA=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_FB_SIMPLE=y

# Early console for debugging
CONFIG_EARLY_PRINTK=y
CONFIG_PRINTK_TIME=y

# Power management
CONFIG_ACPI=y
CONFIG_ACPI_BUTTON=y
CONFIG_CPU_IDLE=y
CONFIG_CPU_IDLE_GOV_LADDER=y

# Enable all CPU features
CONFIG_X86_MSR=y
CONFIG_X86_CPUID=y
CONFIG_PROCESSOR_SELECT=y
CONFIG_CPU_SUP_INTEL=y
CONFIG_CPU_SUP_AMD=y
CONFIG_CPU_SUP_HYGON=y
CONFIG_CPU_SUP_CENTAUR=y
CONFIG_CPU_SUP_ZHAOXIN=y

# EFI support (critical for EFI boot)
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_EFI_BOOTLOADER_CONTROL=y
CONFIG_EFI_PARTITION=y
CONFIG_EFIVAR_FS=y
CONFIG_EFI_VARS_PSTORE=y
CONFIG_EFI_RUNTIME_MAP=y
CONFIG_EFI_MIXED=y

# Firmware loading support
CONFIG_FW_LOADER=y
CONFIG_FIRMWARE_IN_KERNEL=y
CONFIG_EXTRA_FIRMWARE=""

# Security options (minimal)
CONFIG_SECURITY_DMESG_RESTRICT=n

# Required for proper boot
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_PACKET=y

# Disable unnecessary features
CONFIG_SWAP=n
CONFIG_MODULES=n
CONFIG_MODULE_UNLOAD=n
CONFIG_KALLSYMS=y
CONFIG_DEBUG_KERNEL=n
CONFIG_SOUND=n
CONFIG_DRM=n
CONFIG_AGP=n
CONFIG_WIRELESS=n
CONFIG_RFKILL=n
CONFIG_HAMRADIO=n
CONFIG_STAGING=n
EOF

# Apply our config changes
echo -e "${YELLOW}Applying configuration...${NC}"
./scripts/kconfig/merge_config.sh -m .config

# Make sure critical options are set
echo -e "${YELLOW}Ensuring critical options...${NC}"
./scripts/config --enable CONFIG_64BIT
./scripts/config --enable CONFIG_X86_64
./scripts/config --enable CONFIG_SMP
./scripts/config --enable CONFIG_PCI
./scripts/config --enable CONFIG_BLK_DEV_SD
./scripts/config --enable CONFIG_ATA
./scripts/config --enable CONFIG_SATA_AHCI
./scripts/config --enable CONFIG_ATA_PIIX
./scripts/config --enable CONFIG_VIRTIO_BLK
./scripts/config --enable CONFIG_VIRTIO_PCI
./scripts/config --enable CONFIG_EXT4_FS
./scripts/config --enable CONFIG_DEVTMPFS
./scripts/config --enable CONFIG_DEVTMPFS_MOUNT
./scripts/config --enable CONFIG_TMPFS
./scripts/config --enable CONFIG_PROC_FS
./scripts/config --enable CONFIG_SYSFS
# Enable EFI support
./scripts/config --enable CONFIG_EFI
./scripts/config --enable CONFIG_EFI_STUB
./scripts/config --enable CONFIG_EFI_PARTITION
# Enable framebuffer for EFI console
./scripts/config --enable CONFIG_FB
./scripts/config --enable CONFIG_FB_EFI
./scripts/config --enable CONFIG_FB_SIMPLE
./scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE
# Enable USB storage drivers
./scripts/config --enable CONFIG_USB_STORAGE
./scripts/config --enable CONFIG_USB_UAS
# Enable Thunderbolt
./scripts/config --enable CONFIG_THUNDERBOLT

# Finalize config
make olddefconfig

# Show configuration summary
echo -e "${GREEN}Configuration summary:${NC}"
echo "VirtIO support:"
grep -E "CONFIG_VIRTIO|CONFIG_SCSI_VIRTIO" .config | grep "=y"
echo ""
echo "SATA/AHCI support:"
grep -E "CONFIG_SATA_AHCI|CONFIG_ATA_PIIX" .config | grep "=y"
echo ""
echo "SCSI support:"
grep -E "CONFIG_SCSI|CONFIG_BLK_DEV_SD" .config | grep "=y"

# Build kernel
echo -e "${YELLOW}Building kernel (this will take a while)...${NC}"
make -j$(nproc) bzImage

# Copy kernel
echo -e "${GREEN}Kernel built successfully!${NC}"
echo "Kernel location: $BUILD_DIR/linux-${KERNEL_VERSION}/arch/x86/boot/bzImage"
echo ""
echo "Kernel features:"
echo "- All storage drivers built-in (no modules needed)"
echo "- VirtIO support for QEMU/KVM"
echo "- AHCI/SATA support for physical hardware"
echo "- NVMe support"
echo "- Common RAID controllers"
echo "- USB storage support (including specialized chipsets)"
echo "- Thunderbolt support"
echo "- FireWire/IEEE1394 support"
echo ""
echo "To use this kernel, run the ISO build:"
echo "devbox run build"