#!/bin/bash

# Secure SSH Key-Based Authentication Setup Script
# Version: 2.0 - Enhanced Security
# - Uses Ed25519 keys (more secure than RSA)
# - Input validation and sanitization
# - Better error handling
# - Checks for SSH installation
# - Secure file permissions

set -euo pipefail

# Configuration
KEY_TYPE="ed25519"  # More secure than RSA
KEY_BITS=""  # Not needed for Ed25519
KEY_DIR="$HOME/.ssh"
KEY_NAME="id_${KEY_TYPE}"
KEY_PATH="$KEY_DIR/$KEY_NAME"

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
    # Remove dangerous characters and trim whitespace
    echo "$input" | sed 's/[;&|`$]//g' | xargs
}

validate_hostname() {
    local host="$1"
    # Basic hostname/IP validation
    if [[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] && [[ ${#host} -le 253 ]]; then
        return 0
    fi
    return 1
}

validate_username() {
    local user="$1"
    # Basic username validation (alphanumeric, underscore, hyphen)
    if [[ "$user" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#user} -le 32 ]]; then
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v ssh &> /dev/null; then
        log_error "SSH client not found. Please install OpenSSH client."
        exit 1
    fi
    
    if ! command -v ssh-copy-id &> /dev/null; then
        log_error "ssh-copy-id not found. Please install OpenSSH client."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Cleanup function
cleanup() {
    log_warning "Script interrupted. Cleaning up..."
    exit 1
}

trap cleanup INT TERM

main() {
    echo "================================================================================"
    echo "  SECURE SSH KEY-BASED AUTHENTICATION SETUP"
    echo "  Enhanced Security Version 2.0"
    echo "================================================================================"
    echo
    
    check_prerequisites
    
    # Step 1: Ensure .ssh directory exists with proper permissions
    if [ ! -d "$KEY_DIR" ]; then
        log_info "Creating SSH directory: $KEY_DIR"
        mkdir -p "$KEY_DIR"
        chmod 700 "$KEY_DIR"
    else
        # Ensure proper permissions
        chmod 700 "$KEY_DIR"
    fi
    
    # Step 2: Check if key already exists
    if [ -f "$KEY_PATH" ]; then
        log_warning "SSH key already exists at $KEY_PATH"
        log_info "Key type: $(ssh-keygen -l -f "$KEY_PATH" | awk '{print $2}')"
        read_secure "Do you want to generate a new key? (y/N): " GENERATE_NEW
        GENERATE_NEW=$(sanitize_input "$GENERATE_NEW")
        if [[ ! "$GENERATE_NEW" =~ ^[Yy]$ ]]; then
            log_info "Using existing key"
        else
            # Backup existing key
            backup_key="${KEY_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
            mv "$KEY_PATH" "$backup_key"
            mv "${KEY_PATH}.pub" "${backup_key}.pub"
            log_success "Existing key backed up to $backup_key"
        fi
    fi
    
    # Generate new key if needed
    if [ ! -f "$KEY_PATH" ]; then
        log_info "Generating new Ed25519 SSH key pair..."
        if ssh-keygen -t "$KEY_TYPE" -f "$KEY_PATH" -q -N "" -C "$(whoami)@$(hostname)-$(date +%Y%m%d)"; then
            log_success "SSH key pair generated: $KEY_PATH"
            log_info "Key fingerprint: $(ssh-keygen -l -f "$KEY_PATH")"
        else
            log_error "Failed to generate SSH key"
            exit 1
        fi
    fi
    
    echo
    log_info "Enter the target server details:"
    echo
    
    # Get and validate hostname
    while true; do
        read_secure "   Hostname (e.g., myserver): " HOSTNAME
        HOSTNAME=$(sanitize_input "$HOSTNAME")
        if validate_hostname "$HOSTNAME"; then
            break
        else
            log_warning "Invalid hostname format"
        fi
    done
    
    # Get and validate IP
    while true; do
        read_secure "   IP Address (e.g., 192.168.1.100): " IP
        IP=$(sanitize_input "$IP")
        if [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || validate_hostname "$IP"; then
            break
        else
            log_warning "Invalid IP address or hostname format"
        fi
    done
    
    # Get and validate username
    while true; do
        read_secure "   Username on remote server: " REMOTE_USER
        REMOTE_USER=$(sanitize_input "$REMOTE_USER")
        if validate_username "$REMOTE_USER"; then
            break
        else
            log_warning "Invalid username format (alphanumeric, underscore, hyphen only)"
        fi
    done
    
    REMOTE="$REMOTE_USER@$IP"
    
    if [ -z "$HOSTNAME" ] || [ -z "$IP" ] || [ -z "$REMOTE_USER" ]; then
        log_error "All fields are required. Exiting."
        exit 1
    fi
    
    echo
    log_info "Testing basic connectivity to $REMOTE..."
    if ! timeout 10 ping -c 1 "$IP" &> /dev/null; then
        log_warning "Host $IP is not reachable via ping. Continuing anyway..."
        log_warning "Ensure the host is accessible and SSH service is running"
    else
        log_success "Host is pingable."
    fi
    
    echo
    log_info "Attempting to copy SSH public key to $REMOTE..."
    echo "    You will be prompted for the password once."
    
    # Use ssh-copy-id with additional security options
    if ssh-copy-id -i "${KEY_PATH}.pub" -o ConnectTimeout=10 -o StrictHostKeyChecking=ask "$REMOTE"; then
        echo
        log_success "Key copied successfully to $REMOTE."
        log_info "You can now log in using: ssh $REMOTE"
        log_info "(No password required after this)"
    else
        echo
        log_error "Failed to copy SSH key."
        log_error "Common causes:"
        echo "      - Incorrect password"
        echo "      - SSH server not allowing password authentication"
        echo "      - Remote user has no home directory or wrong permissions"
        echo "      - Firewall blocking SSH (port 22)"
        echo "      - Host key verification failed"
        exit 1
    fi
    
    # Optional: Add host to known_hosts with alias if not already present
    echo
    log_info "Adding host alias '$HOSTNAME' to ~/.ssh/config (if not exists)..."
    SSH_CONFIG="$HOME/.ssh/config"
    
    # Ensure config file has proper permissions
    if [ -f "$SSH_CONFIG" ]; then
        chmod 600 "$SSH_CONFIG"
    fi
    
    if ! grep -q "Host $HOSTNAME" "$SSH_CONFIG" 2>/dev/null; then
        cat >> "$SSH_CONFIG" << EOF

Host $HOSTNAME
    HostName $IP
    User $REMOTE_USER
    IdentityFile $KEY_PATH
    Port 22
    StrictHostKeyChecking ask
    UserKnownHostsFile ~/.ssh/known_hosts
EOF
        chmod 600 "$SSH_CONFIG"
        log_success "Host alias '$HOSTNAME' added to SSH config."
        log_info "Now connect with: ssh $HOSTNAME"
    else
        log_success "Host alias '$HOSTNAME' already exists in SSH config."
    fi
    
    echo
    log_success "=== Setup Complete ==="
    log_info "Secure SSH access configured for $REMOTE"
    log_info "Public key fingerprint: $(ssh-keygen -l -f "$KEY_PATH")"
    echo
    log_info "Security Notes:"
    echo "  - Keep your private key secure: $KEY_PATH"
    echo "  - Never share your private key"
    echo "  - Consider using ssh-agent for key management"
    echo "  - Regularly rotate your SSH keys"
}

# Run main function
main

log_success "Script completed successfully!"
exit 0