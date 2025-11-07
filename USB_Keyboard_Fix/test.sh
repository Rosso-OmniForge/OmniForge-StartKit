#!/bin/bash

# ==============================================================================
# ZXWMicroChip ZXW-KEYBOARD Test Script
# ==============================================================================
# This script tests if the ZXWMicroChip keyboard fix has been applied correctly
# and verifies keyboard functionality.
#
# Run this after installing the fix and rebooting.
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Test functions
test_kernel_parameters() {
    log "Testing kernel parameters..."
    
    CMDLINE=$(cat /proc/cmdline)
    
    if echo "$CMDLINE" | grep -q "usbcore.quirks=5566:0008:b"; then
        success "USB quirks present in kernel command line"
    else
        error "USB quirks NOT found in kernel command line"
        error "The fix may not have been applied correctly"
        return 1
    fi
    
    if echo "$CMDLINE" | grep -q "usbcore.use_both_schemes=y"; then
        success "USB enumeration schemes parameter present"
    else
        warning "USB enumeration schemes parameter not found"
    fi
    
    if echo "$CMDLINE" | grep -q "usbcore.initial_descriptor_timeout"; then
        success "USB descriptor timeout parameter present"
    else
        warning "USB descriptor timeout parameter not found"
    fi
}

test_udev_rules() {
    log "Testing udev rules..."
    
    if [[ -f /etc/udev/rules.d/90-zxw-keyboard.rules ]]; then
        success "Udev rules file exists"
        
        if grep -q "5566.*0008" /etc/udev/rules.d/90-zxw-keyboard.rules; then
            success "Udev rules contain correct USB ID"
        else
            error "Udev rules do not contain correct USB ID"
            return 1
        fi
    else
        error "Udev rules file not found"
        return 1
    fi
}

test_hid_modules() {
    log "Testing HID modules..."
    
    if [[ -f /etc/modules-load.d/zxw-keyboard.conf ]]; then
        success "HID modules configuration exists"
    else
        warning "HID modules configuration not found"
    fi
    
    # Check if modules are loaded
    if lsmod | grep -q "hid_generic"; then
        success "hid_generic module loaded"
    else
        warning "hid_generic module not loaded"
    fi
    
    if lsmod | grep -q "usbhid"; then
        success "usbhid module loaded"
    else
        warning "usbhid module not loaded"
    fi
}

test_usb_detection() {
    log "Testing USB device detection..."
    
    if lsusb | grep -q "5566:0008"; then
        success "ZXWMicroChip keyboard detected in USB devices!"
        
        # Get detailed USB info
        USB_INFO=$(lsusb -d 5566:0008)
        log "Device info: $USB_INFO"
        
        return 0
    else
        warning "ZXWMicroChip keyboard NOT detected in USB devices"
        warning "Please ensure the keyboard is connected"
        return 1
    fi
}

test_input_devices() {
    log "Testing input device creation..."
    
    # Check if xinput is available
    if ! command -v xinput &> /dev/null; then
        warning "xinput not available - cannot test input devices"
        return 1
    fi
    
    if xinput list | grep -q -i "zxw"; then
        success "ZXWMicroChip keyboard found in input devices!"
        
        # Show all ZXW devices
        log "Input devices found:"
        xinput list | grep -i "zxw" | while read line; do
            echo "  $line"
        done
        
        return 0
    else
        error "ZXWMicroChip keyboard NOT found in input devices"
        error "The keyboard may not be functioning correctly"
        return 1
    fi
}

test_keyboard_functionality() {
    log "Testing keyboard functionality..."
    
    echo
    echo "Please test your keyboard by typing in this terminal:"
    echo "Type 'test' and press Enter, or press Ctrl+C to skip this test."
    echo
    
    read -p "Keyboard test input: " TEST_INPUT
    
    if [[ -n "$TEST_INPUT" ]]; then
        success "Keyboard input received: '$TEST_INPUT'"
        success "Keyboard appears to be functioning!"
        return 0
    else
        warning "No input received"
        return 1
    fi
}

check_error_logs() {
    log "Checking for USB errors in system logs..."
    
    # Check for the specific error we were fixing
    if sudo dmesg | grep -q "unable to read config index 0 descriptor/start: -71"; then
        error "Still finding USB descriptor errors in dmesg!"
        error "The fix may not be working correctly"
        
        # Show recent errors
        log "Recent USB errors:"
        sudo dmesg | grep "unable to read config index 0" | tail -5 | while read line; do
            echo "  $line"
        done
        
        return 1
    else
        success "No USB descriptor errors found in recent logs"
        return 0
    fi
}

show_system_info() {
    log "System information:"
    echo "  OS: $(lsb_release -d 2>/dev/null | cut -d: -f2 | xargs || echo 'Unknown')"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    
    if [[ -f /proc/device-tree/model ]]; then
        echo "  Hardware: $(cat /proc/device-tree/model)"
    fi
    
    # Check power supply (common issue)
    if [[ -f /sys/class/hwmon/hwmon4/name ]] && grep -q "rpi_volt" /sys/class/hwmon/hwmon4/name 2>/dev/null; then
        log "Checking power supply status..."
        if sudo dmesg | grep -q "Undervoltage detected"; then
            warning "Undervoltage detected in system logs!"
            warning "Consider using official Raspberry Pi power supply"
        else
            success "No power supply issues detected"
        fi
    fi
}

# Main test function
main() {
    echo
    echo "=============================================================================="
    echo "  ZXWMicroChip ZXW-KEYBOARD Test Script"
    echo "=============================================================================="
    echo "This script will test if the keyboard fix has been applied correctly."
    echo
    
    show_system_info
    echo
    
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Run all tests
    echo "Running tests..."
    echo
    
    if test_kernel_parameters; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
    echo
    
    if test_udev_rules; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
    echo
    
    if test_hid_modules; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
    echo
    
    # These tests require the keyboard to be connected
    echo "Hardware tests (keyboard must be connected):"
    echo
    
    if test_usb_detection; then
        ((TESTS_PASSED++))
        
        if test_input_devices; then
            ((TESTS_PASSED++))
        else
            ((TESTS_FAILED++))
        fi
        
        if check_error_logs; then
            ((TESTS_PASSED++))
        else
            ((TESTS_FAILED++))
        fi
        
        echo
        if test_keyboard_functionality; then
            ((TESTS_PASSED++))
        else
            ((TESTS_FAILED++))
        fi
        
    else
        warning "Skipping input device tests (keyboard not detected)"
        ((TESTS_FAILED += 3))
    fi
    
    echo
    echo "=============================================================================="
    echo "Test Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "=============================================================================="
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        success "All tests passed! Your ZXWMicroChip keyboard should be working correctly."
        echo
        echo "Your keyboard is ready to use!"
        
    elif [[ $TESTS_PASSED -ge 3 ]]; then
        warning "Most tests passed, but there may be minor issues."
        echo
        echo "Your keyboard should be working, but check the warnings above."
        
    else
        error "Multiple tests failed. The keyboard fix may not be working correctly."
        echo
        echo "Troubleshooting steps:"
        echo "1. Ensure you have rebooted after running install.sh"
        echo "2. Check that the keyboard is properly connected"
        echo "3. Try different USB ports"
        echo "4. Check power supply (use official Pi adapter)"
        echo "5. Run install.sh again if needed"
        echo
        echo "If problems persist, check the README.md for more troubleshooting steps."
    fi
}

# Run main function
main "$@"