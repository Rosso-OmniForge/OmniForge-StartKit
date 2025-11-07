# OmniForge Development Start Kit

A comprehensive (Red/Purple/Blue) Team starter kit with automated setup scripts, security tools, and documentation.

## Overview

This repository contains a collection of scripts and tools designed to help Red Team operators quickly set up and configure secure environments for penetration testing, security research, and operational security.

## Repository Structure

```
OmniForge-StartKit/
├── New_Installs/
│   └── Raspberry_Pi/
│       └── Pi_5/
│           └── baseinstall.sh          # Comprehensive system setup script
├── SSH/
│   └── secure_connect.sh               # Secure SSH key authentication setup
├── Tools_Used/
│   └── REDTEAM_QUICK_REFERENCE.md      # Extensive tools reference guide
├── USB_Keyboard_Fix/
│   ├── install.sh                      # ZXWMicroChip keyboard fix installer
│   ├── test.sh                         # Keyboard functionality test script
│   └── README.md                       # Detailed fix documentation
└── VPN/
    └── wireguard_setup.sh              # WireGuard VPN setup script
```

## Scripts Overview

### 1. Base Installation Script (`New_Installs/Raspberry_Pi/Pi_5/baseinstall.sh`)

**Purpose**: Automated setup for Debian-based systems with Red Team tools.

**Features**:
- OS detection and compatibility checking
- Raspberry Pi 5 specific optimizations
- Comprehensive tool installation (development, security, web servers)
- Secure credential management
- Windows network share mounting
- Git and GitHub CLI configuration

**Security Enhancements** (v2.0):
- Input validation and sanitization
- Secure credential handling
- Error handling and rollback capabilities
- Non-interactive mode options

**Usage**:
```bash
sudo ./baseinstall.sh
```

**Installed Tools**:
- Firefox, FileZilla, VS Code
- Git, GitHub CLI
- Node.js, npm, Python
- Web servers (nginx, Apache, PHP, MariaDB)
- Docker and container tools
- Red Team tools (nmap, metasploit, wireshark, etc.)
- Social engineering tools (GoPhish, SET)

### 2. Secure SSH Setup (`SSH/secure_connect.sh`)

**Purpose**: Secure SSH key-based authentication setup.

**Features**:
- Ed25519 key generation (more secure than RSA)
- Input validation and sanitization
- Automatic SSH config management
- Prerequisite checking
- Backup of existing keys

**Security Features**:
- Uses modern Ed25519 keys
- Proper file permissions (600 for private keys)
- Host key verification
- Timeout protection

**Usage**:
```bash
./secure_connect.sh
```

**What it does**:
1. Checks for SSH installation
2. Generates Ed25519 key pair (with backup option)
3. Prompts for server details with validation
4. Copies public key to remote server
5. Updates local SSH config
6. Displays security notes

### 3. WireGuard VPN Setup (`VPN/wireguard_setup.sh`)

**Purpose**: Automated WireGuard VPN installation and configuration.

**Features**:
- Client or server setup modes
- Automatic key generation
- Secure key storage
- Network configuration
- Service management

**Usage**:
```bash
sudo ./wireguard_setup.sh
```

**Setup Options**:
1. **VPN Client**: Connect to existing WireGuard server
   - Requires server public key, IP, and port
   - Generates client keys
   - Creates configuration file
   - Establishes connection

2. **VPN Server**: Create new WireGuard server
   - Generates server keys
   - Configures NAT and forwarding
   - Sets up firewall rules
   - Displays server public key for clients

### 4. USB Keyboard Fix (`USB_Keyboard_Fix/install.sh`)

**Purpose**: Fix for ZXWMicroChip ZXW-KEYBOARD (USB ID 5566:0008) on Raspberry Pi Ubuntu.

**Problem Solved**: Resolves USB enumeration failures that prevent the ZXWMicroChip keyboard from working on ARM64 Raspberry Pi systems, while it works perfectly on x86 Ubuntu systems.

**Error Fixed**:
```
usb X-Y: unable to read config index 0 descriptor/start: -71
usb X-Y: can't read configurations, error -71
usb usb2-port1: unable to enumerate USB device
```

**Features**:
- USB quirks for proper enumeration timing
- Power management configuration
- HID module setup for multi-interface support
- Automatic backup and restoration capabilities
- Comprehensive testing suite

**Usage**:
```bash
cd USB_Keyboard_Fix
./install.sh
sudo reboot
./test.sh    # After reboot to verify functionality
```

**What it does**:
1. Adds USB quirks to kernel command line (`usbcore.quirks=5566:0008:b`)
2. Configures udev rules for power management
3. Sets up HID module loading
4. Creates uninstall script for easy removal
5. Tests keyboard functionality

**Supported Hardware**:
- Raspberry Pi 4 Model B
- Raspberry Pi 5 Model B
- Raspberry Pi 400
- Other Pi models (untested but should work)

**Supported OS**: Ubuntu 22.04+ ARM64 on Raspberry Pi

### 5. Red Team Quick Reference (`Tools_Used/REDTEAM_QUICK_REFERENCE.md`)

**Purpose**: Comprehensive reference guide for Red Team tools and techniques.

**Sections**:
- Web Servers (nginx, Apache, PHP)
- Databases (MariaDB)
- Docker containers
- Red Team tools (GoPhish, SET, HTTrack)
- Python security libraries
- SSL/TLS certificates
- Networking tools (nmap, wireshark, tcpdump)
- Web application testing (sqlmap, nikto, burp)
- Exploitation frameworks (Metasploit)
- Post-exploitation tools
- Forensics and analysis
- Social engineering
- Mobile security
- Cloud security (AWS, Azure)
- OPSEC techniques
- Development security
- Log analysis

## Security Considerations

### General Security
- All scripts include input validation and sanitization
- Credentials are handled securely with proper permissions
- Backup mechanisms prevent data loss
- Error handling prevents partial installations

### SSH Security
- Uses Ed25519 keys (more secure than RSA)
- Proper file permissions (700 for .ssh, 600 for keys)
- Host key verification enabled
- No password authentication after key setup

### VPN Security
- WireGuard provides modern cryptography
- Perfect forward secrecy
- Automatic key rotation
- Minimal attack surface

### Operational Security
- Scripts avoid logging sensitive information
- Temporary files are cleaned up
- Network operations use timeouts
- Fallback mechanisms for failures

## Prerequisites

### System Requirements
- Debian-based Linux distribution (Ubuntu, Debian, Raspberry Pi OS)
- Root/sudo access
- Internet connection
- At least 2GB RAM (4GB recommended)
- 10GB free disk space

### Package Dependencies
- curl, wget
- git
- build-essential
- apt-transport-https

## Installation and Usage

### Quick Start
1. Clone the repository:
```bash
git clone https://github.com/Rosso-OmniForge/OmniForge-StartKit.git
cd OmniForge-StartKit
```

2. Make scripts executable:
```bash
chmod +x */*.sh
```

3. Run base installation:
```bash
sudo ./New_Installs/Raspberry_Pi/Pi_5/baseinstall.sh
```

4. Setup SSH keys:
```bash
./SSH/secure_connect.sh
```

5. Configure VPN (optional):
```bash
sudo ./VPN/wireguard_setup.sh
```

### Raspberry Pi 5 Specific
The base installation script includes optimizations for Raspberry Pi 5:
- NVMe stability fixes
- PCIe Gen 3 configuration
- Optimized mount options
- Smartmontools for NVMe monitoring

**Important**: After running on Pi 5, a reboot is required for NVMe fixes to take effect.

### USB Keyboard Issues on Raspberry Pi
If you have a ZXWMicroChip ZXW-KEYBOARD that works on PC but not on Raspberry Pi:
```bash
cd USB_Keyboard_Fix
./install.sh
sudo reboot
```

The keyboard should work normally after reboot. Run `./test.sh` to verify functionality.

## Troubleshooting

### Common Issues

**Script fails with permission denied**:
- Ensure you're running with sudo for installation scripts
- Check file permissions: `chmod +x script.sh`

**Internet connectivity issues**:
- Verify network connection: `ping 8.8.8.8`
- Check DNS: `nslookup google.com`

**Package installation fails**:
- Update package lists: `sudo apt update`
- Check available disk space: `df -h`

**WireGuard connection fails**:
- Check firewall: `sudo ufw status`
- Verify keys: `sudo wg show`
- Check logs: `sudo journalctl -u wg-quick@wg0`

**SSH key authentication fails**:
- Verify key permissions: `ls -la ~/.ssh/`
- Check server SSH config: `ssh -v user@server`
- Ensure authorized_keys is updated on server

**ZXWMicroChip keyboard not working on Pi**:
- Run the USB keyboard fix: `cd USB_Keyboard_Fix && ./install.sh`
- Ensure adequate power supply (use official Pi adapter)
- Try different USB ports
- Check for errors: `sudo dmesg | grep "unable to read config"`
- Run test script after reboot: `./test.sh`

### Logs and Debugging
- Installation logs: `/tmp/baseinstall.log`
- System logs: `sudo journalctl -xe`
- WireGuard logs: `sudo journalctl -u wg-quick@wg0`
- SSH debug: `ssh -v user@server`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Contribution Guidelines
- Follow security best practices
- Include proper error handling
- Add documentation for new features
- Test on multiple platforms
- Use meaningful commit messages

## License

This project is for educational and authorized security testing purposes only. Use responsibly and in compliance with applicable laws and regulations.

## Disclaimer

These tools are provided for legitimate security research and authorized penetration testing. The authors are not responsible for misuse or illegal activities. Always obtain proper authorization before conducting security assessments.

## Support

For issues, questions, or contributions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review the quick reference guide

## Version History

- **v2.0** (November 2025): Major security enhancements, input validation, WireGuard support
- **v1.0** (Initial): Basic installation and setup scripts
