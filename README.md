# Disk Eraser - Secure Hard Drive Wiper

A custom Alpine Linux ISO that automatically overwrites all internal hard drives with random data on boot.

## ⚠️ WARNING ⚠️

**THIS TOOL WILL PERMANENTLY DESTROY ALL DATA ON ALL INTERNAL HARD DRIVES**

- No confirmation prompts
- No way to cancel once started
- Data cannot be recovered
- Use only on systems where you want to permanently erase all data

## Features

- Boots automatically and starts wiping immediately
- Overwrites all internal hard drives with random data from `/dev/urandom`
- Skips USB boot device automatically
- Skips all removable media
- Lightweight Alpine Linux base (~50MB ISO)
- Shows progress during wiping
- Automatically powers off when complete

## Building the ISO

### Requirements

- Linux system with root access
- Internet connection to download Alpine Linux
- Build dependencies (installed automatically by script):
  - wget
  - xorriso
  - squashfs-tools
  - syslinux
  - isolinux

### Build Steps

```bash
cd alpine-wiper
sudo ./build-iso.sh
```

This will create `disk-wiper.iso` in the current directory.

## Creating Bootable USB

```bash
# Find your USB device (be VERY careful to select the right device!)
lsblk

# Write the ISO to USB (replace /dev/sdX with your USB device)
sudo dd if=disk-wiper.iso of=/dev/sdX bs=4M status=progress
```

## Usage

1. Insert the USB stick into the target computer
2. Boot from USB (may need to change BIOS/UEFI settings)
3. System will automatically:
   - Detect all internal hard drives
   - Skip the USB boot device
   - Overwrite each drive with random data
   - Show progress for each drive
   - Power off when complete

## Boot Options

The ISO provides two boot options:

1. **Disk Wiper** (default): Automatically starts wiping after 3 seconds
2. **Safe Mode**: Boots to shell without running wipe script (press Tab at boot menu)

## How It Works

1. Alpine Linux boots from USB
2. Custom init script runs automatically
3. Script identifies all block devices
4. Filters out USB boot device and removable media
5. Writes random data to each internal drive using `dd`
6. Powers off system when complete

## Security Notes

- Uses `/dev/urandom` for cryptographically secure random data
- Overwrites entire drive including partition tables
- Multiple passes can be added by modifying the script
- No logs or data are retained

## Customization

Edit `scripts/wipe-disks.sh` to:
- Add multiple overwrite passes
- Change data source (e.g., `/dev/zero` for faster writes)
- Add specific drive filtering
- Modify completion behavior

## License

Use at your own risk. This tool is provided as-is for legitimate data sanitization purposes only.