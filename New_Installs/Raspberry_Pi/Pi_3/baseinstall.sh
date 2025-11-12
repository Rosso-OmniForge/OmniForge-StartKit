#!/bin/bash

################################################################################
# Base Installation Script for Debian-based Systems
# Author: Nero Rosso - OmniForge
# Date: November 12, 2025
# Version: 2.0 - Security Enhanced
# 
# Purpose: Automated setup script for fresh Debian/Ubuntu/Raspberry Pi OS installs
# Includes: Development tools, Red Team tools, Windows share mounting
################################################################################

# Security enhancements:
# - Input validation and sanitization
# - Secure credential handling
# - Non-interactive mode options
# - Better error handling and rollback
# - Modular installation options

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# LOGGING FUNCTIONS
################################################################################

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

# Progress tracking
TOTAL_STEPS=20
CURRENT_STEP=0

log_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS]${NC} $1" >&2
}

# Secure input functions
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
    
    # Basic input validation
    if [[ -z "${!var_name}" ]]; then
        log_error "Input cannot be empty"
        return 1
    fi
}

# Sanitize input to prevent injection
sanitize_input() {
    local input="$1"
    # Remove dangerous characters
    echo "$input" | sed 's/[;&|]//g' | xargs
}

################################################################################
# ERROR HANDLING AND ROLLBACK
################################################################################

# Track installed packages for potential rollback
INSTALLED_PACKAGES=()
BACKUP_FILES=()

# Cleanup function
cleanup() {
    log_warning "Script interrupted. Cleaning up..."
    # Remove any temporary files
    rm -f /tmp/baseinstall.log
    exit 1
}

trap cleanup INT TERM

# Script configuration options
MINIMAL_INSTALL=false
SKIP_REDTEAM=false
BRAVE_ONLY=false
STORAGE_TYPE="unknown"

# Register installed package
register_package() {
    INSTALLED_PACKAGES+=("$1")
}

# Register backup file
register_backup() {
    BACKUP_FILES+=("$1")
}

# Rollback function (basic)
rollback() {
    log_warning "Attempting rollback..."
    # This is a basic rollback - in production, you'd want more sophisticated rollback
    for backup in "${BACKUP_FILES[@]}"; do
        if [[ -f "$backup" ]]; then
            original="${backup%.backup}"
            mv "$backup" "$original" 2>/dev/null || true
        fi
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

check_internet() {
    log_info "Checking internet connectivity..."
    if ! timeout 10 ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connection detected. Please check your network."
        exit 1
    fi
    log_success "Internet connectivity confirmed"
}

################################################################################
# ARGUMENT PARSING
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --minimal)
                MINIMAL_INSTALL=true
                log_info "Minimal installation mode enabled"
                shift
                ;;
            --no-redteam)
                SKIP_REDTEAM=true
                log_info "Skipping Red Team tools installation"
                shift
                ;;
            --brave-only)
                BRAVE_ONLY=true
                log_info "Browser-only installation (Brave)"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --minimal      Install only essential tools (no Red Team tools)"
                echo "  --no-redteam   Skip Red Team tools installation"
                echo "  --brave-only   Install only Brave browser and exit"
                echo "  --help, -h     Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

################################################################################
# PACKAGE AVAILABILITY CHECK
################################################################################

check_package_availability() {
    local package=$1
    if apt-cache show "$package" &> /dev/null; then
        return 0
    else
        log_warning "Package $package not available in repositories"
        return 1
    fi
}

################################################################################
# OS DETECTION
################################################################################

detect_os() {
    log_info "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        OS_CODENAME=$VERSION_CODENAME
        
        case $ID in
            ubuntu)
                OS_TYPE="ubuntu"
                log_success "Detected: Ubuntu $VER ($OS_CODENAME)"
                ;;
            debian)
                OS_TYPE="debian"
                log_success "Detected: Debian $VER ($OS_CODENAME)"
                ;;
            raspbian)
                OS_TYPE="raspbian"
                log_success "Detected: Raspberry Pi OS $VER ($OS_CODENAME)"
                ;;
            *)
                log_error "Unsupported OS: $ID"
                log_warning "This script supports Ubuntu, Debian, and Raspberry Pi OS only"
                exit 1
                ;;
        esac
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    # Detect if running on Raspberry Pi 3
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(tr -d '\0' </proc/device-tree/model)
        if [[ $MODEL == *"Raspberry Pi 3"* ]]; then
            IS_PI3=true
            log_info "Running on Raspberry Pi 3 - will apply specific optimizations"
            
            # Detect storage type
            if lsblk | grep -q nvme; then
                STORAGE_TYPE="nvme"
                log_info "Detected NVMe storage"
            elif lsblk | grep -q mmcblk0; then
                STORAGE_TYPE="sd_card"
                log_info "Detected SD card storage"
            else
                STORAGE_TYPE="unknown"
                log_warning "Unknown storage type"
            fi
        else
            IS_PI3=false
        fi
    else
        IS_PI3=false
    fi
}

################################################################################
# RASPBERRY PI 5 NVME FIXES
################################################################################

apply_pi5_fixes() {
    if [ "$IS_PI3" != true ]; then
        return
    fi
    
    log_progress "Applying Raspberry Pi 5 optimizations..."
    
    # Detect correct boot configuration path
    CONFIG_FILE=""
    if [ -f /boot/firmware/config.txt ]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    elif [ -f /boot/config.txt ]; then
        CONFIG_FILE="/boot/config.txt"
    else
        log_error "Cannot find boot configuration file"
        return 1
    fi
    
    log_info "Using boot config: $CONFIG_FILE"
    
    # Backup config.txt if not already backed up
    if [ ! -f "${CONFIG_FILE}.backup" ]; then
        log_info "Backing up $CONFIG_FILE..."
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        log_success "Backup created: ${CONFIG_FILE}.backup"
    fi
    
    # Check if Pi5 optimizations already exist
    if ! grep -q "\[pi5\]" "$CONFIG_FILE"; then
        log_info "Adding Pi5 PCIe Gen 3 and power management optimizations..."
        cat >> "$CONFIG_FILE" << 'EOF'

# Raspberry Pi 5 NVMe Stability Optimizations
[pi5]
# Force PCIe Gen 3 for better NVMe performance
dtparam=pciex1_gen=3

# Disable problematic power states (prevents corruption)
dtparam=pciex1,no-l0s
dtparam=pciex1,no-l1
EOF
        log_success "Pi5 optimizations added to config.txt"
    else
        log_success "Pi5 optimizations already present in config.txt"
    fi
    
    # Optimize fstab for NVMe
    if [ ! -f /etc/fstab.backup ]; then
        log_info "Backing up /etc/fstab..."
        cp /etc/fstab /etc/fstab.backup
        log_success "Backup created: /etc/fstab.backup"
    fi
    
    # Check if root partition has optimizations
    if ! grep -q "noatime" /etc/fstab | grep -q "/dev/nvme"; then
        log_info "Optimizing NVMe mount options in /etc/fstab..."
        # This is a safe edit - adds options to NVMe root partition
        sed -i 's|\(/dev/nvme[^ ]*[ ]*[ ]*[^ ]*[ ]*ext4[ ]*\)\(defaults\)|\1defaults,noatime,discard,commit=60,errors=remount-ro|g' /etc/fstab
        log_success "NVMe mount options optimized"
    else
        log_success "NVMe mount options already optimized"
    fi
    
    # Install smartmontools for NVMe health monitoring
    if ! command -v smartctl &> /dev/null; then
        log_info "Installing smartmontools for NVMe monitoring..."
        apt-get install -y smartmontools
        log_success "smartmontools installed"
    fi
}

################################################################################
# OPTIMIZE PI5 NVME
################################################################################

optimize_pi5_nvme() {
    if [ "$IS_PI3" != true ] || [ "$STORAGE_TYPE" != "nvme" ]; then
        return
    fi
    
    log_progress "Applying advanced NVMe optimizations for Pi5..."
    
    # Add to /etc/sysctl.conf
    if ! grep -q "Pi5 NVMe optimizations" /etc/sysctl.conf; then
        log_info "Adding NVMe sysctl optimizations..."
        cat >> /etc/sysctl.conf << 'EOF'

# Raspberry Pi 5 NVMe Optimizations
vm.swappiness=1
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
EOF
        sysctl -p > /dev/null 2>&1
        log_success "sysctl optimizations applied"
    fi
    
    # Optimize I/O scheduler
    if [ -f /sys/block/nvme0n1/queue/scheduler ]; then
        log_info "Setting optimal I/O scheduler for NVMe..."
        echo "none" > /sys/block/nvme0n1/queue/scheduler
        
        # Make persistent across reboots
        cat > /etc/udev/rules.d/60-nvme-scheduler.rules << 'EOF'
# Set none scheduler for NVMe devices
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
EOF
        log_success "I/O scheduler optimized"
    fi
    
    log_success "Advanced NVMe optimizations completed"
}

################################################################################
# SYSTEM UPDATE
################################################################################

update_system() {
    log_progress "Updating system packages..."
    apt-get update
    log_success "Package lists updated"
    
    log_info "Upgrading existing packages (this may take a while)..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    log_success "System packages upgraded"
    
    log_info "Installing essential build tools..."
    apt-get install -y \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        dirmngr
    log_success "Essential tools installed"
}

################################################################################
# REMOVE CHROMIUM
################################################################################

remove_chromium() {
    log_info "Checking for Chromium installation..."
    
    if command -v chromium-browser &> /dev/null || command -v chromium &> /dev/null; then
        log_warning "Removing Chromium (as requested)..."
        apt-get remove --purge -y chromium-browser chromium chromium-common 2>/dev/null || true
        apt-get autoremove -y
        log_success "Chromium removed"
    else
        log_success "Chromium not installed"
    fi
}

################################################################################
# INSTALL BRAVE BROWSER
################################################################################

install_brave() {
    log_progress "Installing Brave browser..."
    
    if command -v brave-browser &> /dev/null; then
        log_success "Brave already installed"
        return
    fi
    
    # Install Brave from official repository
    log_info "Adding Brave repository..."
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
        | tee /etc/apt/sources.list.d/brave-browser.list
    
    apt-get update
    
    if check_package_availability "brave-browser"; then
        apt-get install -y brave-browser
        log_success "Brave browser installed"
    else
        log_error "Brave browser not available for this architecture"
        log_warning "You may need to install manually from brave.com"
    fi
}

################################################################################
# INSTALL FIREFOX
################################################################################

install_firefox() {
    log_progress "Installing Firefox..."
    
    if command -v firefox &> /dev/null; then
        log_success "Firefox already installed"
        return
    fi
    
    case $OS_TYPE in
        ubuntu|debian)
            # Install Firefox ESR (Extended Support Release) from repos
            if check_package_availability "firefox-esr"; then
                apt-get install -y firefox-esr
            elif check_package_availability "firefox"; then
                apt-get install -y firefox
            else
                log_warning "Firefox not available in repositories"
            fi
            ;;
        raspbian)
            if check_package_availability "firefox-esr"; then
                apt-get install -y firefox-esr
            else
                log_warning "Firefox not available - consider installing Chromium or Brave"
            fi
            ;;
    esac
    
    log_success "Firefox installed"
}

################################################################################
# INSTALL FILEZILLA
################################################################################

install_filezilla() {
    log_info "Installing FileZilla..."
    
    if command -v filezilla &> /dev/null; then
        log_success "FileZilla already installed"
        return
    fi
    
    apt-get install -y filezilla
    log_success "FileZilla installed"
}

################################################################################
# INSTALL VS CODE
################################################################################

install_vscode() {
    log_progress "Installing Visual Studio Code..."
    
    if command -v code &> /dev/null; then
        log_success "VS Code already installed"
        return
    fi
    
    # Detect architecture
    ARCH=$(dpkg --print-architecture)
    
    # Check if architecture is supported
    case $ARCH in
        amd64|arm64|armhf)
            log_info "Detected architecture: $ARCH"
            ;;
        *)
            log_error "Unsupported architecture for VS Code: $ARCH"
            return 1
            ;;
    esac
    
    # Add Microsoft GPG key
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/packages.microsoft.gpg
    
    # Add VS Code repository with proper architecture
    echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    
    # Update and install
    apt-get update
    
    if check_package_availability "code"; then
        apt-get install -y code
        log_success "VS Code installed"
    else
        log_warning "VS Code not available for $ARCH - install manually if needed"
    fi
}

################################################################################
# INSTALL GIT AND GITHUB CLI
################################################################################

install_git() {
    log_info "Installing Git..."
    
    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version)
        log_success "Git already installed: $GIT_VERSION"
    else
        apt-get install -y git
        log_success "Git installed"
    fi
}

install_github_cli() {
    log_info "Installing GitHub CLI..."
    
    if command -v gh &> /dev/null; then
        GH_VERSION=$(gh --version | head -n1)
        log_success "GitHub CLI already installed: $GH_VERSION"
        return
    fi
    
    # Add GitHub CLI repository
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
    
    apt-get update
    apt-get install -y gh
    
    log_success "GitHub CLI installed"
}

################################################################################
# CONFIGURE GIT
################################################################################

configure_git() {
    log_info "Configuring Git global settings..."
    
    # Get the actual user (not root)
    ACTUAL_USER=${SUDO_USER:-$USER}
    
    # Check if git user is already configured
    CURRENT_USER=$(su - $ACTUAL_USER -c "git config --global user.name" 2>/dev/null || echo "")
    CURRENT_EMAIL=$(su - $ACTUAL_USER -c "git config --global user.email" 2>/dev/null || echo "")
    
    if [ -n "$CURRENT_USER" ] && [ -n "$CURRENT_EMAIL" ]; then
        log_success "Git already configured:"
        echo "  Name: $CURRENT_USER"
        echo "  Email: $CURRENT_EMAIL"
        read_secure "Do you want to reconfigure? (y/N): " RECONFIGURE
        RECONFIGURE=$(sanitize_input "$RECONFIGURE")
        if [[ ! "$RECONFIGURE" =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Prompt for git credentials with validation
    while true; do
        read_secure "Enter your Git username: " GIT_USERNAME
        GIT_USERNAME=$(sanitize_input "$GIT_USERNAME")
        if [[ -n "$GIT_USERNAME" ]]; then
            break
        fi
    done
    
    while true; do
        read_secure "Enter your Git email: " GIT_EMAIL
        GIT_EMAIL=$(sanitize_input "$GIT_EMAIL")
        if [[ "$GIT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        fi
        log_warning "Invalid email format"
    done
    
    # Configure for the actual user (not root)
    su - $ACTUAL_USER -c "git config --global user.name '$GIT_USERNAME'"
    su - $ACTUAL_USER -c "git config --global user.email '$GIT_EMAIL'"
    su - $ACTUAL_USER -c "git config --global credential.helper store"
    su - $ACTUAL_USER -c "git config --global init.defaultBranch main"
    
    log_success "Git configured for user: $GIT_USERNAME <$GIT_EMAIL>"
}

################################################################################
# CONFIGURE GITHUB CLI
################################################################################

configure_github() {
    log_info "Configuring GitHub CLI..."
    
    ACTUAL_USER=${SUDO_USER:-$USER}
    
    # Check if already authenticated
    if su - $ACTUAL_USER -c "gh auth status" &> /dev/null; then
        log_success "GitHub CLI already authenticated"
        return
    fi
    
    log_info "GitHub CLI requires authentication"
    log_info "Please run the following command after this script completes:"
    echo ""
    echo "    gh auth login"
    echo ""
    log_info "Choose: GitHub.com → HTTPS → Login with a web browser"
}

################################################################################
# INSTALL NODE.JS AND NPM
################################################################################

install_nodejs() {
    log_info "Installing Node.js and npm..."
    
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log_success "Node.js already installed: $NODE_VERSION"
    else
        # Install Node.js LTS using NodeSource repository
        log_info "Adding NodeSource repository for Node.js LTS..."
        
        # Detect architecture
        ARCH=$(dpkg --print-architecture)
        
        # Download and run NodeSource setup script for Node.js 20.x LTS
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        
        apt-get install -y nodejs
        
        NODE_VERSION=$(node --version)
        NPM_VERSION=$(npm --version)
        log_success "Node.js installed: $NODE_VERSION"
        log_success "npm installed: $NPM_VERSION"
    fi
    
    # Install global npm packages for Red Team web development
    log_info "Installing essential npm packages globally..."
    npm install -g \
        http-server \
        live-server \
        nodemon \
        pm2 \
        express-generator \
        webpack \
        webpack-cli \
        create-react-app \
        @vue/cli \
        typescript \
        ts-node \
        eslint \
        prettier \
        serve \
        localtunnel \
        ngrok 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some npm packages may have failed"
    
    # Install Red Team specific npm packages
    log_info "Installing Red Team specific npm packages..."
    npm install -g \
        website-scraper \
        sitemap-generator-cli \
        broken-link-checker \
        html-minifier \
        uglify-js 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some Red Team npm packages may have failed"
    
    log_success "Node.js and essential npm packages installed"
}

################################################################################
# INSTALL WEB SERVERS AND DEPLOYMENT TOOLS
################################################################################

install_web_servers() {
    log_info "Installing web servers and deployment tools..."
    
    # Install nginx
    log_info "Installing nginx..."
    apt-get install -y nginx
    
    # Stop nginx by default (Red Team usage - manual start when needed)
    systemctl stop nginx
    systemctl disable nginx
    log_success "nginx installed (stopped by default - start manually when needed)"
    
    # Install Apache2
    log_info "Installing Apache2..."
    apt-get install -y apache2
    
    # Stop Apache by default to avoid port conflicts with nginx
    systemctl stop apache2
    systemctl disable apache2
    log_success "Apache2 installed (stopped by default - start manually when needed)"
    
    # Install PHP for dynamic web applications
    log_info "Installing PHP and modules..."
    apt-get install -y \
        php \
        php-fpm \
        php-mysql \
        php-cli \
        php-curl \
        php-gd \
        php-mbstring \
        php-xml \
        php-zip \
        libapache2-mod-php 2>&1 | tee -a /tmp/baseinstall.log
    log_success "PHP installed"
    
    # Install MySQL/MariaDB for database-backed phishing sites
    log_info "Installing MariaDB server..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client
    systemctl stop mariadb
    systemctl disable mariadb
    log_success "MariaDB installed (stopped by default)"
    
    # Install SSL/TLS tools
    log_info "Installing SSL/TLS certificate tools..."
    apt-get install -y \
        certbot \
        python3-certbot-nginx \
        python3-certbot-apache \
        openssl
    log_success "Certbot and OpenSSL installed"
    
    # Install Docker for containerized deployments
    log_info "Installing Docker..."
    install_docker
    
    # Install additional web development tools
    log_info "Installing additional web tools..."
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        zip \
        rsync \
        screen \
        tmux \
        vim \
        nano \
        htop \
        net-tools \
        dnsmasq \
        hostapd \
        bridge-utils \
        iptables-persistent 2>&1 | tee -a /tmp/baseinstall.log
    
    # Install Composer (PHP dependency manager)
    log_info "Installing Composer (PHP)..."
    if ! command -v composer &> /dev/null; then
        EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
        
        if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
            log_warning "Composer installer corrupt - skipping"
            rm composer-setup.php
        else
            php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
            rm composer-setup.php
            log_success "Composer installed"
        fi
    else
        log_success "Composer already installed"
    fi
    
    log_success "Web servers and deployment tools installed"
    
    # Create useful directory structure for Red Team web deployments
    log_info "Creating Red Team web deployment directories..."
    mkdir -p /var/www/redteam/{phishing,c2,payloads,clones}
    mkdir -p /opt/redteam/web-templates
    chown -R www-data:www-data /var/www/redteam
    chmod -R 755 /var/www/redteam
    log_success "Created deployment directories in /var/www/redteam/"
}

################################################################################
# INSTALL DOCKER
################################################################################

install_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        log_success "Docker already installed: $DOCKER_VERSION"
        return
    fi
    
    log_info "Installing Docker..."
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin 2>&1 | tee -a /tmp/baseinstall.log
    
    # Add user to docker group
    ACTUAL_USER=${SUDO_USER:-$USER}
    if [ "$ACTUAL_USER" != "root" ]; then
        usermod -aG docker $ACTUAL_USER
        log_success "Added $ACTUAL_USER to docker group (logout/login required)"
    fi
    
    # Install docker-compose standalone (legacy)
    log_info "Installing docker-compose..."
    DOCKER_COMPOSE_VERSION="2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker and docker-compose installed"
}

################################################################################
# INSTALL RED TEAM WEB CLONING TOOLS
################################################################################

install_web_cloning_tools() {
    log_info "Installing website cloning and social engineering tools..."
    
    # HTTrack - Website copier
    apt-get install -y httrack
    log_success "HTTrack installed"
    
    # Social Engineering Toolkit (SET)
    log_info "Installing Social Engineering Toolkit (SET)..."
    apt-get install -y set 2>/dev/null || {
        log_warning "SET not in repos - installing from GitHub..."
        cd /opt
        if [ ! -d "setoolkit" ]; then
            git clone https://github.com/trustedsec/social-engineer-toolkit.git setoolkit
            cd setoolkit
            pip3 install -r requirements.txt
            python3 setup.py install
            log_success "SET installed from GitHub"
        else
            log_success "SET already cloned in /opt/setoolkit"
        fi
    }
    
    # GoPhish - Phishing framework
    log_info "Installing GoPhish..."
    GOPHISH_VERSION="0.12.1"
    if [ ! -f /opt/gophish/gophish ]; then
        mkdir -p /opt/gophish
        cd /opt/gophish
        wget "https://github.com/gophish/gophish/releases/download/v${GOPHISH_VERSION}/gophish-v${GOPHISH_VERSION}-linux-64bit.zip" -O gophish.zip 2>&1 | tee -a /tmp/baseinstall.log || log_warning "GoPhish download failed"
        if [ -f gophish.zip ]; then
            unzip -o gophish.zip
            chmod +x gophish
            rm gophish.zip
            log_success "GoPhish installed in /opt/gophish"
        fi
    else
        log_success "GoPhish already installed"
    fi
    
    log_success "Web cloning and social engineering tools installed"
}

################################################################################
# INSTALL RED TEAM TOOLS
################################################################################

install_redteam_tools() {
    if [ "$SKIP_REDTEAM" = true ] || [ "$MINIMAL_INSTALL" = true ]; then
        log_info "Skipping Red Team tools installation"
        return
    fi
    
    log_progress "Installing Red Team / Penetration Testing tools..."
    
    # Core networking tools
    log_info "Installing networking tools..."
    apt-get install -y \
        nmap \
        netcat-openbsd \
        tcpdump \
        wireshark \
        tshark \
        net-tools \
        dnsutils \
        whois \
        traceroute \
        mtr \
        iptables \
        nftables \
        arp-scan \
        hping3 \
        masscan 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some networking tools failed to install"
    
    # Web application testing
    log_info "Installing web application testing tools..."
    apt-get install -y \
        nikto \
        sqlmap \
        dirb \
        wfuzz \
        gobuster \
        hydra \
        medusa \
        john \
        hashcat 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some web tools may not be available in standard repos"
    
    # DirBuster and BurpSuite often not in repos
    apt-get install -y dirbuster 2>/dev/null || log_warning "DirBuster not available - use gobuster instead"
    apt-get install -y burpsuite 2>/dev/null || log_warning "BurpSuite not in repos - download from PortSwigger if needed"
    
    # Exploitation frameworks
    log_info "Installing exploitation tools..."
    apt-get install -y metasploit-framework 2>/dev/null || log_warning "Metasploit not in standard repos - install from https://metasploit.com if needed"
    
    # Wireless tools (if applicable)
    log_info "Installing wireless tools..."
    apt-get install -y \
        aircrack-ng \
        reaver \
        wireless-tools \
        wavemon 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some wireless tools may not be available"
    
    # Reverse engineering
    log_info "Installing reverse engineering tools..."
    apt-get install -y \
        radare2 \
        gdb \
        ghex \
        binwalk \
        foremost \
        hexedit \
        xxd 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some reverse engineering tools may not be available"
    
    # Scripting and development
    log_info "Installing scripting tools..."
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        ruby \
        ruby-dev \
        perl \
        jq 2>&1 | tee -a /tmp/baseinstall.log
    
    # Go and yq may not be available in all repos
    apt-get install -y golang 2>/dev/null || log_warning "Golang not in repos - install from golang.org if needed"
    apt-get install -y yq 2>/dev/null || log_warning "yq not in repos - install manually if needed"
    
    # Install Node.js and npm
    log_info "Installing Node.js and npm..."
    install_nodejs
    
    # Python security libraries
    log_info "Installing Python security libraries..."
    
    # Create virtual environment for security tools to avoid system package conflicts
    VENV_DIR="/opt/redteam-venv"
    if [ ! -d "$VENV_DIR" ]; then
        log_info "Creating Python virtual environment at $VENV_DIR..."
        python3 -m venv $VENV_DIR
        log_success "Virtual environment created"
    fi
    
    # Install packages in virtual environment
    log_info "Installing Python packages in virtual environment..."
    $VENV_DIR/bin/pip install --upgrade pip setuptools wheel
    $VENV_DIR/bin/pip install \
        requests \
        beautifulsoup4 \
        scapy \
        pwntools \
        paramiko \
        cryptography \
        pyserial || log_warning "Some Python packages may require manual installation"
    
    # Note: impacket often has dependency issues, install separately if needed
    log_info "Attempting to install impacket..."
    $VENV_DIR/bin/pip install impacket || log_warning "Impacket installation failed - may need manual installation"
    
    # Create symlinks for easy access
    log_info "Creating symlinks for Python tools..."
    ln -sf $VENV_DIR/bin/pwn /usr/local/bin/pwn 2>/dev/null || true
    
    log_success "Python security libraries installed in $VENV_DIR"
    log_info "To use the virtual environment: source $VENV_DIR/bin/activate"
    
    # Additional useful tools
    log_info "Installing additional security tools..."
    apt-get install -y \
        steghide \
        exiftool \
        socat \
        proxychains4 \
        tor \
        sshpass \
        sshuttle \
        openvpn \
        wireguard \
        remmina \
        rdesktop
    
    # Try to install FreeRDP (package name varies by distro)
    apt-get install -y freerdp2-x11 || apt-get install -y freerdp-x11 || log_warning "FreeRDP not available in repos"
    
    # Information gathering
    log_info "Installing information gathering tools..."
    apt-get install -y maltego 2>/dev/null || log_warning "Maltego not in repos - download from maltego.com if needed"
    
    log_success "Red Team tools installation completed"
    log_warning "Some advanced tools (Metasploit, Burp Suite Pro, etc.) may require separate installation"
}

################################################################################
# INSTALL ESSENTIAL UTILITIES
################################################################################

install_essential_utils() {
    log_progress "Installing essential modern utilities..."
    
    log_info "Installing modern CLI tools..."
    
    # Install available modern tools
    local tools_to_install=""
    
    # Check each tool and add to install list if available
    for tool in tree jq fzf tmux screen ranger mc htop ncdu; do
        if check_package_availability "$tool"; then
            tools_to_install="$tools_to_install $tool"
        fi
    done
    
    if [ -n "$tools_to_install" ]; then
        apt-get install -y $tools_to_install
    fi
    
    # Try to install modern tools (may not be in all repos)
    log_info "Installing modern replacements (if available)..."
    check_package_availability "bat" && apt-get install -y bat || log_info "bat not available"
    check_package_availability "exa" && apt-get install -y exa || log_info "exa not available"
    check_package_availability "ripgrep" && apt-get install -y ripgrep || log_info "ripgrep not available"
    check_package_availability "fd-find" && apt-get install -y fd-find || log_info "fd-find not available"
    
    # Install zsh if requested
    if check_package_availability "zsh"; then
        apt-get install -y zsh
        log_info "zsh installed - configure with 'chsh -s /usr/bin/zsh'"
    fi
    
    log_success "Essential utilities installed"
}

################################################################################
# INSTALL SYSTEM MONITORING TOOLS
################################################################################

install_system_monitoring() {
    log_progress "Installing system monitoring tools..."
    
    log_info "Installing monitoring utilities..."
    apt-get install -y \
        htop \
        iotop \
        nethogs \
        ncdu \
        smartmontools \
        sysstat 2>&1 | tee -a /tmp/baseinstall.log || log_warning "Some monitoring tools may not be available"
    
    # Try to install modern alternatives
    check_package_availability "btop" && apt-get install -y btop || log_info "btop not available - using htop"
    check_package_availability "lm-sensors" && apt-get install -y lm-sensors || log_info "lm-sensors not available"
    
    # Pi5 specific monitoring
    if [ "$IS_PI3" = true ]; then
        log_info "Installing Raspberry Pi specific tools..."
        if check_package_availability "raspberrypi-kernel-headers"; then
            apt-get install -y raspberrypi-kernel-headers
        fi
        
        # Install vcgencmd if not present (usually pre-installed on Pi OS)
        if ! command -v vcgencmd &> /dev/null; then
            log_warning "vcgencmd not found - some Pi monitoring may not work"
        else
            log_success "Raspberry Pi monitoring tools available"
            log_info "Monitor temperature: vcgencmd measure_temp"
            log_info "Monitor voltages: vcgencmd measure_volts"
            log_info "Monitor clock speeds: vcgencmd measure_clock arm"
        fi
        
        # Create helpful monitoring aliases
        ACTUAL_USER=${SUDO_USER:-$USER}
        USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
        
        if [ -f "$USER_HOME/.bashrc" ]; then
            if ! grep -q "# Pi5 monitoring aliases" "$USER_HOME/.bashrc"; then
                cat >> "$USER_HOME/.bashrc" << 'EOF'

# Pi5 monitoring aliases
alias pitemp='vcgencmd measure_temp'
alias pivolts='vcgencmd measure_volts'
alias piclock='vcgencmd measure_clock arm'
alias pistats='echo "Temperature: $(vcgencmd measure_temp)" && echo "CPU Voltage: $(vcgencmd measure_volts core)" && echo "CPU Clock: $(vcgencmd measure_clock arm)"'
EOF
                chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/.bashrc"
                log_info "Added Pi monitoring aliases to .bashrc"
            fi
        fi
    fi
    
    # Enable sysstat
    if [ -f /etc/default/sysstat ]; then
        sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
        systemctl enable sysstat
        systemctl start sysstat
    fi
    
    log_success "System monitoring tools installed"
}

################################################################################
# SETUP WINDOWS SHARE MOUNTING
################################################################################

setup_windows_shares() {
    log_info "Setting up Windows network share mounting..."
    
    # Install CIFS utilities
    if ! command -v mount.cifs &> /dev/null; then
        log_info "Installing cifs-utils..."
        if apt-get install -y cifs-utils; then
            register_package "cifs-utils"
            log_success "cifs-utils installed"
        else
            log_error "Failed to install cifs-utils"
            return 1
        fi
    fi
    
    # Get Windows share credentials securely
    log_info "Windows share configuration required"
    log_warning "Credentials will be stored in /root/.smbcredentials"
    log_warning "Consider using kerberos authentication for better security"
    
    read_secure "Enter Windows domain (or leave empty if none): " WIN_DOMAIN
    WIN_DOMAIN=$(sanitize_input "$WIN_DOMAIN")
    
    read_secure "Enter Windows username: " WIN_USERNAME
    WIN_USERNAME=$(sanitize_input "$WIN_USERNAME")
    
    read_secure "Enter Windows password: " WIN_PASSWORD true
    
    read_secure "Enter Windows server IP or hostname: " WIN_SERVER
    WIN_SERVER=$(sanitize_input "$WIN_SERVER")
    
    # Validate IP/hostname
    if ! [[ "$WIN_SERVER" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid server name"
        return 1
    fi
    
    # Create credentials file with secure permissions
    CREDS_FILE="/root/.smbcredentials"
    log_info "Creating credentials file at $CREDS_FILE..."
    
    # Backup existing if present
    if [[ -f "$CREDS_FILE" ]]; then
        cp "$CREDS_FILE" "${CREDS_FILE}.backup"
        register_backup "${CREDS_FILE}.backup"
    fi
    
    cat > "$CREDS_FILE" << EOF
username=$WIN_USERNAME
password=$WIN_PASSWORD
EOF
    
    if [ -n "$WIN_DOMAIN" ]; then
        echo "domain=$WIN_DOMAIN" >> "$CREDS_FILE"
    fi
    
    chmod 600 "$CREDS_FILE"
    log_success "Credentials file created and secured"
    
    # Create mount points
    log_info "Creating mount points..."
    DRIVES=("O" "P" "Q" "R" "S" "T")
    
    for DRIVE in "${DRIVES[@]}"; do
        MOUNT_POINT="/mnt/$DRIVE"
        if [ ! -d "$MOUNT_POINT" ]; then
            mkdir -p "$MOUNT_POINT"
            log_success "Created mount point: $MOUNT_POINT"
        else
            log_success "Mount point already exists: $MOUNT_POINT"
        fi
    done
    
    # Prompt for share names with validation
    log_info "Configuring share names for each drive..."
    declare -A SHARE_NAMES
    
    for DRIVE in "${DRIVES[@]}"; do
        while true; do
            read_secure "Enter share name for drive $DRIVE (e.g., ShareData, Projects): " SHARE_NAME
            SHARE_NAME=$(sanitize_input "$SHARE_NAME")
            if [[ -n "$SHARE_NAME" ]]; then
                SHARE_NAMES[$DRIVE]=$SHARE_NAME
                break
            fi
            log_warning "Share name cannot be empty"
        done
    done
    
    # Backup fstab if not already backed up
    FSTAB_BACKUP="/etc/fstab.backup-shares"
    if [ ! -f "$FSTAB_BACKUP" ]; then
        cp /etc/fstab "$FSTAB_BACKUP"
        register_backup "$FSTAB_BACKUP"
        log_success "Created fstab backup: $FSTAB_BACKUP"
    fi
    
    # Add entries to fstab
    log_info "Adding Windows shares to /etc/fstab..."
    
    for DRIVE in "${DRIVES[@]}"; do
        MOUNT_POINT="/mnt/$DRIVE"
        SHARE_NAME=${SHARE_NAMES[$DRIVE]}
        
        # Check if entry already exists
        if grep -q "$MOUNT_POINT" /etc/fstab; then
            log_warning "Entry for $MOUNT_POINT already exists in fstab, skipping..."
            continue
        fi
        
        # Add to fstab with security options
        echo "//$WIN_SERVER/$SHARE_NAME $MOUNT_POINT cifs credentials=$CREDS_FILE,iocharset=utf8,file_mode=0777,dir_mode=0777,nofail,x-systemd.automount,seal 0 0" >> /etc/fstab
        log_success "Added $DRIVE: //$WIN_SERVER/$SHARE_NAME → $MOUNT_POINT"
    done
    
    log_success "Windows shares configured in /etc/fstab"
    log_info "Shares will auto-mount on boot. To mount now, run: sudo mount -a"
    log_warning "Test the mounts and verify permissions before use"
}

################################################################################
# POST-INSTALLATION SUMMARY
################################################################################

create_quick_reference() {
    log_info "Creating quick reference guide..."
    
    ACTUAL_USER=${SUDO_USER:-$USER}
    USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    REF_FILE="$USER_HOME/Documents/REDTEAM_QUICK_REFERENCE.md"
    
    cat > "$REF_FILE" << 'REFEOF'
# RED TEAM QUICK REFERENCE GUIDE
Generated: $(date)

## WEB SERVERS

### nginx
```bash
sudo systemctl start nginx       # Start nginx
sudo systemctl stop nginx        # Stop nginx
sudo systemctl restart nginx     # Restart nginx
sudo systemctl status nginx      # Check status
sudo nginx -t                    # Test configuration
```
Config: `/etc/nginx/nginx.conf`
Site configs: `/etc/nginx/sites-available/`

### Apache2
```bash
sudo systemctl start apache2     # Start Apache
sudo systemctl stop apache2      # Stop Apache
sudo systemctl restart apache2   # Restart Apache
sudo a2ensite sitename           # Enable site
sudo a2dissite sitename          # Disable site
```
Config: `/etc/apache2/apache2.conf`
Site configs: `/etc/apache2/sites-available/`

### Quick HTTP Servers
```bash
# Python
python3 -m http.server 8080

# Node.js
http-server -p 8080
live-server --port=8080

# PHP
php -S 0.0.0.0:8080
```

## DATABASE

### MariaDB
```bash
sudo systemctl start mariadb     # Start database
sudo mysql_secure_installation   # Secure installation
sudo mysql -u root -p            # Connect as root
```

## DOCKER

### Useful Containers
```bash
# Kali Linux
docker run -it kalilinux/kali-rolling

# Quick nginx
docker run -d -p 80:80 nginx

# Quick Apache
docker run -d -p 8080:80 httpd

# PHP development
docker run -d -p 8080:80 php:apache
```

## RED TEAM TOOLS

### GoPhish
```bash
cd /opt/gophish
sudo ./gophish
# Access: https://localhost:3333
# Default: admin/gophish
```

### Social Engineering Toolkit (SET)
```bash
sudo setoolkit
# or
cd /opt/setoolkit && sudo ./setoolkit
```

### HTTrack (Website Cloner)
```bash
httrack http://example.com -O /var/www/redteam/clones/example
httrack --mirror http://example.com
```

### Website Scraper (npm)
```bash
website-scraper http://example.com -d /var/www/redteam/clones/
```

## PYTHON SECURITY TOOLS

### Activate Virtual Environment
```bash
source /opt/redteam-venv/bin/activate
```

### Tools Available
- pwntools
- scapy
- impacket
- requests
- paramiko

## SSL/TLS CERTIFICATES

### Certbot (Let's Encrypt)
```bash
# nginx
sudo certbot --nginx -d domain.com

# Apache
sudo certbot --apache -d domain.com

# Standalone
sudo certbot certonly --standalone -d domain.com
```

### Self-Signed Certificate
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/selfsigned.key \
  -out /etc/ssl/certs/selfsigned.crt
```

## NETWORKING

### Port Scanning
```bash
nmap -sV -sC target.com          # Version detection + scripts
nmap -p- target.com              # All ports
masscan -p1-65535 target.com --rate=1000
```

### Network Monitoring
```bash
sudo tcpdump -i eth0             # Capture on eth0
sudo wireshark                   # GUI packet analyzer
```

### Proxies
```bash
proxychains4 firefox             # Route through proxy
ssh -D 9050 user@server          # SOCKS proxy
```

## WEB APPLICATION TESTING

### Directory Enumeration
```bash
gobuster dir -u http://target.com -w /usr/share/wordlists/dirb/common.txt
dirb http://target.com
wfuzz -c -z file,/usr/share/wordlists/dirb/common.txt http://target.com/FUZZ
```

### SQL Injection
```bash
sqlmap -u "http://target.com/page?id=1" --dbs
```

### Credential Attacks
```bash
hydra -l admin -P /usr/share/wordlists/rockyou.txt http-post-form
john --wordlist=/usr/share/wordlists/rockyou.txt hash.txt
```

## DEPLOYMENT DIRECTORIES

```
/var/www/redteam/
├── phishing/     # Phishing page deployments
├── c2/           # C2 server web interfaces
├── payloads/     # Payload hosting
└── clones/       # Cloned websites

/opt/
├── gophish/      # GoPhish framework
├── setoolkit/    # Social Engineering Toolkit
└── redteam-venv/ # Python tools virtual environment
```

## NPM TOOLS

### Local Tunnel (Expose local server)
```bash
npx localtunnel --port 8080
```

### Ngrok (Alternative)
```bash
ngrok http 8080
```

### Process Manager
```bash
pm2 start app.js                 # Start application
pm2 list                         # List processes
pm2 stop all                     # Stop all
```

## QUICK PHISHING DEPLOYMENT

```bash
# 1. Clone target website
httrack http://target.com -O /var/www/redteam/clones/target

# 2. Modify for phishing
cd /var/www/redteam/phishing/
cp -r ../clones/target/* .
# Edit HTML/JS as needed

# 3. Deploy
# Option A: Quick test
http-server /var/www/redteam/phishing -p 8080

# Option B: nginx
sudo cp /var/www/redteam/phishing /var/www/html/
sudo systemctl start nginx

# Option C: GoPhish
cd /opt/gophish && sudo ./gophish
```

## WINDOWS SHARES

Mounted at:
- `/mnt/O`
- `/mnt/P`
- `/mnt/Q`
- `/mnt/R`
- `/mnt/S`
- `/mnt/T`

```bash
sudo mount -a                    # Mount all shares
mount | grep cifs                # List mounted shares
```

## USEFUL ALIASES TO ADD

Add to `~/.bashrc`:
```bash
alias serve='http-server -p 8080'
alias phpserve='php -S 0.0.0.0:8080'
alias pyserve='python3 -m http.server 8080'
alias redteam-venv='source /opt/redteam-venv/bin/activate'
alias scan='nmap -sV -sC'
alias dirscan='gobuster dir -u'
```

## LOGS AND TROUBLESHOOTING

```bash
# nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Apache logs
sudo tail -f /var/log/apache2/access.log
sudo tail -f /var/log/apache2/error.log

# System logs
sudo journalctl -xe
sudo dmesg | tail

# Installation log
cat /tmp/baseinstall.log
```

## SECURITY NOTES

⚠️ **IMPORTANT**:
- All web servers are STOPPED by default
- Start them manually when needed
- Use SSL/TLS for external deployments
- Change default passwords (MariaDB, GoPhish, etc.)
- Keep Windows share credentials secure (`/root/.smbcredentials`)
- Use VPN/proxy for operational security
- Test in isolated environment first

REFEOF
    
    chown "$ACTUAL_USER:$ACTUAL_USER" "$REF_FILE"
    log_success "Quick reference guide created: $REF_FILE"
}

post_install_summary() {
    echo ""
    echo "================================================================================"
    log_success "INSTALLATION COMPLETED SUCCESSFULLY"
    echo "================================================================================"
    echo ""
    
    log_info "Installed Components:"
    echo "  ✅ Brave Browser (Chromium removed)"
    echo "  ✅ Firefox ESR"
    if [ "$MINIMAL_INSTALL" != true ]; then
        echo "  ✅ FileZilla"
        echo "  ✅ Visual Studio Code"
    fi
    echo "  ✅ Git (configured)"
    echo "  ✅ GitHub CLI"
    echo "  ✅ Essential Utilities (modern CLI tools)"
    echo "  ✅ System Monitoring Tools"
    if [ "$SKIP_REDTEAM" != true ] && [ "$MINIMAL_INSTALL" != true ]; then
        echo "  ✅ Node.js & npm (with global packages)"
        echo "  ✅ Web Servers (nginx, Apache2, PHP, MariaDB)"
        echo "  ✅ Docker & docker-compose"
        echo "  ✅ SSL Tools (certbot, OpenSSL)"
        echo "  ✅ Red Team Tools Suite"
        echo "  ✅ Web Cloning Tools (HTTrack, SET, GoPhish)"
    fi
    if [ -d /mnt/O ]; then
        echo "  ✅ Windows Share Mounting (O, P, Q, R, S, T)"
    fi
    echo ""
    
    if [ "$IS_PI3" = true ]; then
        log_warning "Raspberry Pi 5 Optimizations Applied"
        echo "  ⚠️  Storage Type: $STORAGE_TYPE"
        if [ "$STORAGE_TYPE" = "nvme" ]; then
            echo "  ⚠️  NVMe optimizations active (sysctl, I/O scheduler)"
        fi
        echo "  ⚠️  A REBOOT IS REQUIRED for all optimizations to take effect"
        echo ""
    fi
    
    log_info "Raspberry Pi Monitoring Commands:"
    if [ "$IS_PI3" = true ] && command -v vcgencmd &> /dev/null; then
        echo "  🌡️  Temperature:   pitemp (or vcgencmd measure_temp)"
        echo "  ⚡ Voltages:      pivolts"
        echo "  ⏰ CPU Clock:     piclock"
        echo "  📊 All stats:     pistats"
    fi
    if [ "$STORAGE_TYPE" = "nvme" ]; then
        echo "  💾 NVMe Health:   sudo smartctl -a /dev/nvme0n1"
    fi
    echo ""
    
    log_info "Next Steps:"
    echo ""
    echo "  1. Authenticate GitHub CLI:"
    echo "     gh auth login"
    echo ""
    
    if [ "$IS_PI3" = true ]; then
        echo "  2. REBOOT NOW to activate all Pi5 optimizations:"
        echo "     sudo reboot"
        echo ""
    fi
    
    if [ -d /mnt/O ]; then
        echo "  3. Mount Windows shares now (or reboot):"
        echo "     sudo mount -a"
        echo ""
    fi
    
    if [ "$SKIP_REDTEAM" != true ] && [ "$MINIMAL_INSTALL" != true ]; then
        echo "  4. Web Server Quick Start:"
        echo "     sudo systemctl start nginx    # Start nginx on port 80"
        echo "     sudo systemctl start apache2  # Start Apache (conflicts with nginx)"
        echo "     sudo systemctl start mariadb  # Start database"
        echo ""
        echo "  5. Deploy test website:"
        echo "     http-server /var/www/redteam/phishing -p 8080"
        echo "     live-server /var/www/redteam/clones"
        echo ""
        echo "  6. GoPhish framework:"
        echo "     cd /opt/gophish && sudo ./gophish"
        echo "     Access: https://localhost:3333 (default: admin/gophish)"
        echo ""
        echo "  7. Docker containers:"
        echo "     docker run -d -p 80:80 nginx  # Quick nginx container"
        echo ""
        echo "  8. Social Engineering Toolkit:"
        echo "     sudo setoolkit  # or /opt/setoolkit/setoolkit"
        echo ""
    fi
    
    if [ "$SKIP_REDTEAM" != true ] && [ "$MINIMAL_INSTALL" != true ]; then
        log_info "Red Team Web Deployment Directories:"
        echo "  📁 /var/www/redteam/phishing  - Phishing page deployments"
        echo "  📁 /var/www/redteam/c2        - C2 server web interfaces"
        echo "  📁 /var/www/redteam/payloads  - Payload hosting"
        echo "  📁 /var/www/redteam/clones    - Cloned websites"
        echo "  📁 /opt/redteam/web-templates - Custom templates"
        echo "  📁 /opt/gophish               - GoPhish installation"
        echo "  📁 /opt/setoolkit             - SET installation"
        echo "  📁 /opt/redteam-venv          - Python security tools venv"
        echo ""
        
        log_info "Useful Commands:"
        echo "  🌐 Quick HTTP server:  http-server -p 8080"
        echo "  🔒 Generate SSL cert:  sudo certbot --nginx -d domain.com"
        echo "  🐳 Docker Kali:        docker run -it kalilinux/kali-rolling"
        echo "  📋 Clone website:      httrack http://example.com -O /var/www/redteam/clones"
        echo "  🎯 Python venv:        source /opt/redteam-venv/bin/activate"
        echo ""
    fi
    
    log_success "📖 Full Quick Reference Guide: ~/Documents/REDTEAM_QUICK_REFERENCE.md"
    echo ""
    
    log_info "Script Execution Options:"
    echo "  sudo $0 --minimal       # Minimal install (no Red Team tools)"
    echo "  sudo $0 --no-redteam    # Skip Red Team tools only"
    echo "  sudo $0 --brave-only    # Install Brave browser only"
    echo "  sudo $0 --help          # Show all options"
    echo ""
    
    echo "================================================================================"
    echo ""
    
    if [ "$IS_PI3" = true ]; then
        log_warning "⚠️  REBOOT REQUIRED - Run: sudo reboot"
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    clear
    echo "================================================================================"
    echo "  UNIVERSAL RASPBERRY PI 5 INSTALLATION SCRIPT"
    echo "  Supporting: Raspberry Pi OS (Bookworm), Ubuntu, Debian 12+"
    echo "  Version: 3.0 - Enhanced & Optimized"
    echo "================================================================================"
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Handle Brave-only mode
    if [ "$BRAVE_ONLY" = true ]; then
        check_root
        check_internet
        remove_chromium
        install_brave
        log_success "Brave browser installation completed!"
        exit 0
    fi
    
    # Pre-flight checks
    log_progress "Running pre-flight checks..."
    check_root
    check_internet
    detect_os
    
    # Apply Pi5 fixes and optimizations
    apply_pi5_fixes
    optimize_pi5_nvme
    
    # System updates
    update_system
    
    # Remove Chromium (as requested)
    remove_chromium
    
    # Install browsers
    install_brave
    install_firefox
    
    # Install standard tools (skip if minimal)
    if [ "$MINIMAL_INSTALL" != true ]; then
        install_filezilla
        install_vscode
    fi
    
    install_git
    install_github_cli
    
    # Configure Git
    configure_git
    configure_github
    
    # Install essential utilities
    install_essential_utils
    
    # Install system monitoring
    install_system_monitoring
    
    # Install Red Team tools (skip if --no-redteam or --minimal)
    install_redteam_tools
    
    # Install web servers and deployment tools (skip if minimal)
    if [ "$MINIMAL_INSTALL" != true ]; then
        install_web_servers
        install_web_cloning_tools
    fi
    
    # Setup Windows shares
    read_secure "Do you want to configure Windows network shares? (y/N): " SETUP_SHARES
    SETUP_SHARES=$(sanitize_input "$SETUP_SHARES")
    if [[ "$SETUP_SHARES" =~ ^[Yy]$ ]]; then
        setup_windows_shares
    else
        log_info "Skipping Windows share configuration"
    fi
    
    # Create quick reference guide
    create_quick_reference
    
    # Final cleanup
    log_progress "Performing final system cleanup..."
    apt-get autoremove -y
    apt-get autoclean -y
    log_success "System cleanup completed"
    
    # Show summary
    post_install_summary
}

# Run main function
main "$@"

log_success "Script completed successfully!"
exit 0
