#!/bin/bash

# WireGuard VPN Installation and Connection Script
# Version: 1.0
# Author: Red Team Engineer
# Date: November 6, 2025
#
# This script installs WireGuard, generates keys if needed,
# and sets up a VPN connection. It asks for server details
# and prints public keys for server configuration.

set -euo pipefail

# Configuration
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_DIR="/etc/wireguard"
CONFIG_FILE="${WG_DIR}/${WG_INTERFACE}.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Input validation and sanitization
sanitize_input() {
    local input="$1"
    # Remove dangerous characters
    echo "$input" | sed 's/[;&|`$]//g' | xargs
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Check each octet
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

read_secure() {
    local prompt="$1"
    local var_name="$2"
    local hidden="${3:-false}"
    
    if [[ "$hidden" == "true" ]]; then
        read -s -p "$prompt" "$var_name"
        echo >&2
    else
        read -p "$prompt" "$var_name"
    fi
    
    # Trim whitespace
    eval "$var_name=\"\${$var_name// /}\""
    
    if [[ -z "${!var_name}" ]]; then
        log_error "Input cannot be empty"
        return 1
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

# Check internet connectivity
check_internet() {
    log_info "Checking internet connectivity..."
    if ! timeout 10 ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connection detected"
        exit 1
    fi
    log_success "Internet connectivity confirmed"
}

# Install WireGuard
install_wireguard() {
    log_info "Installing WireGuard..."
    
    if command -v wg &> /dev/null; then
        log_success "WireGuard already installed: $(wg --version)"
        return
    fi
    
    # Update package list
    apt-get update
    
    # Install WireGuard
    if apt-get install -y wireguard wireguard-tools; then
        log_success "WireGuard installed successfully"
    else
        log_error "Failed to install WireGuard"
        exit 1
    fi
}

# Generate WireGuard keys
generate_keys() {
    local key_dir="$1"
    
    log_info "Generating WireGuard key pair..."
    
    if [[ ! -d "$key_dir" ]]; then
        mkdir -p "$key_dir"
        chmod 700 "$key_dir"
    fi
    
    local private_key_file="${key_dir}/private.key"
    local public_key_file="${key_dir}/public.key"
    
    # Generate private key
    wg genkey > "$private_key_file"
    chmod 600 "$private_key_file"
    
    # Generate public key from private key
    wg pubkey < "$private_key_file" > "$public_key_file"
    chmod 644 "$public_key_file"
    
    log_success "Keys generated:"
    log_info "  Private key: $private_key_file"
    log_info "  Public key: $public_key_file"
    
    # Display public key
    echo
    log_info "YOUR PUBLIC KEY (share this with the server admin):"
    echo "========================================"
    cat "$public_key_file"
    echo "========================================"
    echo
}

# Setup as client
setup_client() {
    local key_dir="$1"
    
    log_info "Setting up WireGuard as client..."
    
    # Generate keys if they don't exist
    if [[ ! -f "${key_dir}/private.key" ]]; then
        generate_keys "$key_dir"
    fi
    
    # Get server details
    echo
    log_info "Enter server connection details:"
    echo
    
    # Get server public key
    while true; do
        read_secure "Server public key: " SERVER_PUBKEY
        SERVER_PUBKEY=$(sanitize_input "$SERVER_PUBKEY")
        # Basic validation - should be 44 characters (base64 encoded)
        if [[ ${#SERVER_PUBKEY} -eq 44 ]]; then
            break
        else
            log_warning "Invalid public key format (should be 44 characters)"
        fi
    done
    
    # Get server endpoint
    while true; do
        read_secure "Server IP address: " SERVER_IP
        SERVER_IP=$(sanitize_input "$SERVER_IP")
        if validate_ip "$SERVER_IP"; then
            break
        else
            log_warning "Invalid IP address format"
        fi
    done
    
    read_secure "Server port (default 51820): " SERVER_PORT
    SERVER_PORT=$(sanitize_input "$SERVER_PORT")
    SERVER_PORT=${SERVER_PORT:-51820}
    
    # Get client IP
    read_secure "Client IP address (e.g., 10.0.0.2): " CLIENT_IP
    CLIENT_IP=$(sanitize_input "$CLIENT_IP")
    CLIENT_IP=${CLIENT_IP:-10.0.0.2}
    
    # Get DNS (optional)
    read_secure "DNS server (optional, press enter for none): " DNS_SERVER
    DNS_SERVER=$(sanitize_input "$DNS_SERVER")
    
    # Create configuration
    log_info "Creating WireGuard configuration..."
    
    cat > "$CONFIG_FILE" << EOF
[Interface]
PrivateKey = $(cat "${key_dir}/private.key")
Address = ${CLIENT_IP}/24
EOF

    if [[ -n "$DNS_SERVER" ]]; then
        echo "DNS = $DNS_SERVER" >> "$CONFIG_FILE"
    fi

    cat >> "$CONFIG_FILE" << EOF

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration created: $CONFIG_FILE"
    
    # Enable and start service
    log_info "Enabling and starting WireGuard interface..."
    systemctl enable wg-quick@${WG_INTERFACE}
    systemctl start wg-quick@${WG_INTERFACE}
    
    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
        log_success "WireGuard VPN connected!"
        echo
        log_info "Connection status:"
        wg show ${WG_INTERFACE}
    else
        log_error "Failed to start WireGuard interface"
        log_info "Check logs with: sudo journalctl -u wg-quick@${WG_INTERFACE}"
        exit 1
    fi
}

# Setup as server
setup_server() {
    local key_dir="$1"
    
    log_info "Setting up WireGuard as server..."
    
    # Generate keys if they don't exist
    if [[ ! -f "${key_dir}/private.key" ]]; then
        generate_keys "$key_dir"
    fi
    
    # Get server configuration
    echo
    log_info "Enter server configuration details:"
    echo
    
    read_secure "Server IP address (e.g., 10.0.0.1): " SERVER_IP
    SERVER_IP=$(sanitize_input "$SERVER_IP")
    SERVER_IP=${SERVER_IP:-10.0.0.1}
    
    # Get network interface for NAT
    read_secure "Network interface for NAT (e.g., eth0): " NAT_INTERFACE
    NAT_INTERFACE=$(sanitize_input "$NAT_INTERFACE")
    NAT_INTERFACE=${NAT_INTERFACE:-eth0}
    
    # Create server configuration
    log_info "Creating server configuration..."
    
    cat > "$CONFIG_FILE" << EOF
[Interface]
PrivateKey = $(cat "${key_dir}/private.key")
Address = ${SERVER_IP}/24
ListenPort = ${WG_PORT}
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NAT_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NAT_INTERFACE} -j MASQUERADE
EOF
    
    chmod 600 "$CONFIG_FILE"
    log_success "Server configuration created: $CONFIG_FILE"
    
    # Enable IP forwarding
    log_info "Enabling IP forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sysctl -p
    
    # Enable and start service
    log_info "Enabling and starting WireGuard interface..."
    systemctl enable wg-quick@${WG_INTERFACE}
    systemctl start wg-quick@${WG_INTERFACE}
    
    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
        log_success "WireGuard server started!"
        echo
        log_info "Server public key (share with clients):"
        echo "========================================"
        cat "${key_dir}/public.key"
        echo "========================================"
        echo
        log_info "Server configuration:"
        wg show ${WG_INTERFACE}
        echo
        log_info "To add clients, run: sudo wg set ${WG_INTERFACE} peer <client_public_key> allowed-ips <client_ip>/32"
    else
        log_error "Failed to start WireGuard interface"
        log_info "Check logs with: sudo journalctl -u wg-quick@${WG_INTERFACE}"
        exit 1
    fi
}

# Main function
main() {
    echo "================================================================================"
    echo "  WIREGUARD VPN INSTALLATION AND CONNECTION SCRIPT"
    echo "  Version 1.0 - Secure VPN Setup"
    echo "================================================================================"
    echo
    
    check_root
    check_internet
    install_wireguard
    
    echo
    log_info "WireGuard Setup Options:"
    echo "  1) Setup as VPN Client (connect to existing server)"
    echo "  2) Setup as VPN Server (create new VPN server)"
    echo
    
    while true; do
        read_secure "Choose option (1 or 2): " SETUP_TYPE
        case "$SETUP_TYPE" in
            1)
                setup_client "$WG_DIR"
                break
                ;;
            2)
                setup_server "$WG_DIR"
                break
                ;;
            *)
                log_warning "Invalid option. Please choose 1 or 2."
                ;;
        esac
    done
    
    echo
    log_success "WireGuard setup completed!"
    echo
    log_info "Management commands:"
    echo "  Check status: sudo wg show"
    echo "  Stop VPN: sudo wg-quick down ${WG_INTERFACE}"
    echo "  Start VPN: sudo wg-quick up ${WG_INTERFACE}"
    echo "  View logs: sudo journalctl -u wg-quick@${WG_INTERFACE}"
}

# Cleanup function
cleanup() {
    log_warning "Script interrupted. Cleaning up..."
    exit 1
}

trap cleanup INT TERM

# Run main function
main

log_success "Script completed successfully!"
exit 0