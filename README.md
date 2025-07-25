# Universal Disk Wiper

A bootable ISO that automatically wipes ALL internal hard drives without user interaction.

## ⚠️ WARNING

**This ISO will IMMEDIATELY and AUTOMATICALLY wipe ALL internal hard drives when booted!**

- No confirmation prompts
- No user interaction required
- Wipes begin immediately after boot
- ALL data will be PERMANENTLY DESTROYED

## Features

- **Universal Hardware Support**: Works on physical servers, desktops, and VMs
- **BIOS and UEFI Boot**: Supports both legacy BIOS and modern UEFI systems
- **Custom Linux Kernel**: Built with all storage drivers compiled in (no module loading required)
- **Storage Support**: SATA, NVMe, SAS, RAID controllers, VirtIO, USB storage
- **Automatic Detection**: Finds and wipes all internal drives
- **Boot Device Protection**: Skips mounted/boot devices
- **Zero Dependencies**: Completely self-contained

## Building

### Prerequisites

Install [Devbox](https://www.jetpack.io/devbox/):
```bash
curl -fsSL https://get.jetpack.io/devbox | bash
```

### Build the ISO

```bash
# Clone the repository
git clone <repository-url>
cd disk-eraser

# Build the custom kernel (only needed once)
devbox run build-kernel

# Build the disk wiper ISO
devbox run build

# The ISO will be created as: disk-wiper.iso
```

### Clean Build Artifacts

```bash
devbox run clean
```

## Technical Details

- **Base**: Custom Linux kernel 6.6.13 LTS
- **Init System**: Minimal busybox-based init
- **Boot Process**:
  1. Kernel boots with all drivers built-in
  2. Init script runs automatically
  3. Detects all block devices
  4. Wipes partition tables and boot sectors
  5. Powers off when complete

## Testing

**⚠️ ONLY test in isolated VMs with no important data!**

```bash
# Test with QEMU (BIOS mode)
qemu-system-x86_64 -m 2048 -cdrom disk-wiper.iso -hda test-disk.img

# Test with QEMU (UEFI mode)
qemu-system-x86_64 -m 2048 -cdrom disk-wiper.iso -hda test-disk.img -bios /usr/share/ovmf/OVMF.fd
```

## Files

- `build-disk-wiper.sh` - Main build script for the ISO
- `build-custom-kernel.sh` - Builds the custom kernel with all drivers
- `devbox.json` - Development environment configuration
- `disk-wiper.iso` - The built ISO (after running build)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**WARNING**: This tool is designed for secure data destruction. Use at your own risk.