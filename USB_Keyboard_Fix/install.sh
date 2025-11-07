#!/bin/bash

# ==============================================================================
# ZXWMicroChip ZXW-KEYBOARD Fix for Raspberry Pi Ubuntu
# ==============================================================================
# This script fixes USB descriptor reading issues (-71 EPROTO errors) that 
# prevent the ZXWMicroChip ZXW-KEYBOARD (ID 5566:0008) from working on
# Raspberry Pi Ubuntu systems.
#
# The keyboard works fine on standard x86 Ubuntu but fails on ARM64 Pi Ubuntu
# due to USB controller timing and power management differences.
#
# Author: GitHub Copilot & Nero
# Date: November 7, 2025
# ==============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should NOT be run as root. Please run as a regular user."
        error "The script will use sudo when needed."
        exit 1
    fi
}

# Check if running on Raspberry Pi
check_raspberry_pi() {
    if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        warning "This script is designed for Raspberry Pi systems."
        warning "It may not be necessary on other hardware."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# Check if keyboard is detected (but not working)
check_keyboard_presence() {
    log "Checking for ZXWMicroChip keyboard..."
    
    if lsusb | grep -q "5566:0008"; then
        success "ZXWMicroChip ZXW-KEYBOARD detected!"
        KEYBOARD_DETECTED=true
    else
        warning "ZXWMicroChip ZXW-KEYBOARD not currently detected."
        warning "This is normal if the keyboard is failing to enumerate."
        KEYBOARD_DETECTED=false
    fi
    
    # Check for the specific error in dmesg
    if sudo dmesg | grep -q "unable to read config index 0 descriptor/start: -71"; then
        warning "Found USB descriptor error -71 in system logs."
        warning "This confirms the keyboard enumeration issue."
    fi
}

# Backup current configuration
backup_config() {
    log "Creating backups..."
    
    # Backup cmdline.txt
    if [[ -f /boot/firmware/current/cmdline.txt ]]; then
        sudo cp /boot/firmware/current/cmdline.txt /boot/firmware/current/cmdline.txt.backup.$(date +%Y%m%d_%H%M%S)
        success "Backed up cmdline.txt"
    elif [[ -f /boot/firmware/cmdline.txt ]]; then
        sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup.$(date +%Y%m%d_%H%M%S)
        success "Backed up cmdline.txt"
    else
        warning "Could not find cmdline.txt to backup"
    fi
}

# Install USB quirks and kernel parameters
install_usb_quirks() {
    log "Installing USB quirks and kernel parameters..."
    
    # Determine the correct cmdline.txt path
    CMDLINE_PATH=""
    if [[ -f /boot/firmware/current/cmdline.txt ]]; then
        CMDLINE_PATH="/boot/firmware/current/cmdline.txt"
    elif [[ -f /boot/firmware/cmdline.txt ]]; then
        CMDLINE_PATH="/boot/firmware/cmdline.txt"
    else
        error "Could not find cmdline.txt file!"
        exit 1
    fi
    
    log "Using cmdline.txt at: $CMDLINE_PATH"
    
    # Get current cmdline content
    CURRENT_CMDLINE=$(cat /proc/cmdline)
    
    # Check if quirks are already present
    if echo "$CURRENT_CMDLINE" | grep -q "usbcore.quirks=5566:0008"; then
        warning "USB quirks already present in kernel command line"
        return 0
    fi
    
    # Add our USB quirks and timing parameters
    NEW_PARAMS="usbcore.quirks=5566:0008:b usbcore.use_both_schemes=y usbcore.initial_descriptor_timeout=10000"
    
    # Create new cmdline
    echo "$CURRENT_CMDLINE $NEW_PARAMS" | sudo tee "$CMDLINE_PATH" > /dev/null
    
    success "Added USB quirks to kernel command line"
    log "Added parameters: $NEW_PARAMS"
}

# Install udev rules
install_udev_rules() {
    log "Installing udev rules..."
    
    # Create udev rule for power management
    sudo tee /etc/udev/rules.d/90-zxw-keyboard.rules > /dev/null << 'EOF'
# ZXWMicroChip ZXW-KEYBOARD power management fix
# Disable autosuspend for this specific keyboard to prevent enumeration issues
SUBSYSTEM=="usb", ATTRS{idVendor}=="5566", ATTRS{idProduct}=="0008", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"

# Additional rules for the keyboard's multiple interfaces
SUBSYSTEM=="usb", ATTRS{idVendor}=="5566", ATTRS{idProduct}=="0008", ATTR{power/control}="on"
EOF
    
    success "Created udev rules for ZXWMicroChip keyboard"
}

# Install additional HID modules configuration
install_hid_modules() {
    log "Configuring HID modules..."
    
    # Ensure required modules are loaded at boot
    sudo tee /etc/modules-load.d/zxw-keyboard.conf > /dev/null << 'EOF'
# Modules required for ZXWMicroChip ZXW-KEYBOARD
hid_generic
hid_multitouch
usbhid
EOF
    
    success "Configured HID modules for auto-loading"
}

# Create uninstall script
create_uninstall_script() {
    log "Creating uninstall script..."
    
    cat > uninstall.sh << 'EOF'
#!/bin/bash

# Uninstall script for ZXWMicroChip ZXW-KEYBOARD fix

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log "Uninstalling ZXWMicroChip ZXW-KEYBOARD fix..."

# Remove udev rules
if [[ -f /etc/udev/rules.d/90-zxw-keyboard.rules ]]; then
    sudo rm /etc/udev/rules.d/90-zxw-keyboard.rules
    success "Removed udev rules"
fi

# Remove modules configuration
if [[ -f /etc/modules-load.d/zxw-keyboard.conf ]]; then
    sudo rm /etc/modules-load.d/zxw-keyboard.conf
    success "Removed HID modules configuration"
fi

# Restore cmdline.txt from backup
BACKUP_FILE=$(ls /boot/firmware/current/cmdline.txt.backup.* 2>/dev/null | tail -1 || ls /boot/firmware/cmdline.txt.backup.* 2>/dev/null | tail -1 || echo "")

if [[ -n "$BACKUP_FILE" ]]; then
    CMDLINE_PATH="/boot/firmware/current/cmdline.txt"
    [[ -f "$CMDLINE_PATH" ]] || CMDLINE_PATH="/boot/firmware/cmdline.txt"
    
    sudo cp "$BACKUP_FILE" "$CMDLINE_PATH"
    success "Restored cmdline.txt from backup: $BACKUP_FILE"
    warning "Reboot required to restore original kernel parameters"
else
    warning "No backup found. Please manually remove USB quirks from cmdline.txt"
    warning "Remove: usbcore.quirks=5566:0008:b usbcore.use_both_schemes=y usbcore.initial_descriptor_timeout=10000"
fi

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

log "Uninstall complete. Reboot recommended."
EOF

    chmod +x uninstall.sh
    success "Created uninstall.sh script"
}

# Create documentation
create_documentation() {
    log "Creating documentation..."
    
    cat > README.md << 'EOF'
# ZXWMicroChip ZXW-KEYBOARD Fix for Raspberry Pi

## Problem Description

The ZXWMicroChip ZXW-KEYBOARD (USB ID 5566:0008) works perfectly on standard x86 Ubuntu systems but fails to enumerate on Raspberry Pi Ubuntu systems with the following error:

```
usb X-Y: unable to read config index 0 descriptor/start: -71
usb X-Y: can't read configurations, error -71
usb usb2-port1: unable to enumerate USB device
```

This is caused by USB controller timing differences and power management issues specific to ARM64 Raspberry Pi systems.

## What This Fix Does

1. **Adds USB quirks** to the kernel command line specifically for the ZXWMicroChip keyboard
2. **Configures power management** to prevent autosuspend issues
3. **Loads required HID modules** for multi-interface keyboard support
4. **Sets descriptor timeout** to allow more time for USB enumeration

## Installation

```bash
sudo chmod +x install.sh
./install.sh
sudo reboot
```

## Verification

After reboot, connect your keyboard and verify:

```bash
# Check if keyboard is detected
lsusb | grep "5566:0008"

# Check if input devices are created
xinput list | grep -i zxw

# Check for any remaining errors
sudo dmesg | grep -i "unable to read config"
```

## Supported Systems

- Raspberry Pi 4 Model B
- Raspberry Pi 5 Model B
- Ubuntu 22.04+ on ARM64
- Other Raspberry Pi models (untested but should work)

## Troubleshooting

If the keyboard still doesn't work:

1. Check power supply (use official Pi power adapter)
2. Try different USB ports
3. Check `sudo dmesg` for other error messages
4. Run the uninstall script and try manual configuration

## Files Modified

- `/boot/firmware/cmdline.txt` or `/boot/firmware/current/cmdline.txt`
- `/etc/udev/rules.d/90-zxw-keyboard.rules`
- `/etc/modules-load.d/zxw-keyboard.conf`

## Uninstall

```bash
./uninstall.sh
sudo reboot
```

## Technical Details

The fix applies these kernel parameters:
- `usbcore.quirks=5566:0008:b` - Reset resume quirk for timing issues
- `usbcore.use_both_schemes=y` - Use both enumeration schemes
- `usbcore.initial_descriptor_timeout=10000` - Longer timeout for slow devices

## License

MIT License - Feel free to use and modify as needed.
EOF
    
    success "Created README.md documentation"
}

# Apply changes immediately (without reboot)
apply_immediate_changes() {
    log "Applying immediate changes..."
    
    # Reload udev rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    
    # Load HID modules
    sudo modprobe hid_generic 2>/dev/null || true
    sudo modprobe hid_multitouch 2>/dev/null || true
    sudo modprobe usbhid 2>/dev/null || true
    
    success "Applied immediate changes"
}

# Test keyboard functionality
test_keyboard() {
    log "Testing for keyboard presence..."
    
    echo
    echo "Please connect your ZXWMicroChip ZXW-KEYBOARD now and wait 10 seconds..."
    echo "Press Ctrl+C if you want to skip this test."
    echo
    
    # Give user time to connect keyboard
    for i in {10..1}; do
        echo -n -e "\rWaiting... $i seconds "
        sleep 1
    done
    echo
    
    # Check if keyboard is now working
    if lsusb | grep -q "5566:0008"; then
        success "Keyboard detected in USB device list!"
        
        if xinput list 2>/dev/null | grep -q -i "zxw"; then
            success "Keyboard detected in input device list!"
            success "Keyboard appears to be working!"
        else
            warning "Keyboard detected but not showing in input devices"
            warning "A reboot may be required for full functionality"
        fi
    else
        warning "Keyboard not detected yet"
        warning "This is normal - the kernel parameters require a reboot to take effect"
    fi
}

# Main installation function
main() {
    echo
    echo "=============================================================================="
    echo "  ZXWMicroChip ZXW-KEYBOARD Fix for Raspberry Pi Ubuntu"
    echo "=============================================================================="
    echo "This script will install fixes for USB descriptor enumeration issues"
    echo "that prevent the ZXWMicroChip ZXW-KEYBOARD from working on Raspberry Pi."
    echo
    
    # Perform checks
    check_root
    check_raspberry_pi
    check_keyboard_presence
    
    echo
    log "Starting installation..."
    
    # Create backups
    backup_config
    
    # Install all fixes
    install_usb_quirks
    install_udev_rules
    install_hid_modules
    
    # Apply immediate changes
    apply_immediate_changes
    
    # Create additional files
    create_uninstall_script
    create_documentation
    
    # Test if possible
    if [[ "$KEYBOARD_DETECTED" == "true" ]]; then
        test_keyboard
    fi
    
    echo
    echo "=============================================================================="
    success "Installation completed successfully!"
    echo "=============================================================================="
    echo
    echo "IMPORTANT: A reboot is required for the kernel parameter changes to take effect."
    echo
    echo "After reboot:"
    echo "1. Connect your ZXWMicroChip ZXW-KEYBOARD"
    echo "2. Run 'lsusb | grep 5566:0008' to verify detection"
    echo "3. Run 'xinput list' to see if input devices are created"
    echo
    echo "Files created:"
    echo "- install.sh (this script)"
    echo "- uninstall.sh (removal script)"
    echo "- README.md (documentation)"
    echo
    echo "To uninstall: ./uninstall.sh"
    echo
    warning "Reboot now? (recommended)"
    read -p "Reboot system? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting system..."
        sudo reboot
    else
        warning "Remember to reboot before testing the keyboard!"
    fi
}

# Run main function
main "$@"