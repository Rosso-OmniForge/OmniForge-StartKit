#!/bin/bash

# Nero's Gaming Arsenal - Debian 13 Ultimate Gaming Platform
# Transform your machine into a high-performance gaming powerhouse
# Author: Nero
# Date: $(date +%Y-%m-%d)
# Version: 2.0

# Terminal color palette
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ASCII Art Header
echo -e "${PURPLE}${BOLD}"
cat << "EOF"

███╗   ██╗███████╗██████╗  ██████╗ ███████╗    ██████╗  █████╗ ███╗   ███╗██╗███╗   ██╗ ██████╗ 
████╗  ██║██╔════╝██╔══██╗██╔═══██╗██╔════╝   ██╔════╝ ██╔══██╗████╗ ████║██║████╗  ██║██╔════╝ 
██╔██╗ ██║█████╗  ██████╔╝██║   ██║███████╗   ██║  ███╗███████║██╔████╔██║██║██╔██╗ ██║██║  ███╗
██║╚██╗██║██╔══╝  ██╔══██╗██║   ██║╚════██║   ██║   ██║██╔══██║██║╚██╔╝██║██║██║╚██╗██║██║   ██║
██║ ╚████║███████╗██║  ██║╚██████╔╝███████║   ╚██████╔╝██║  ██║██║ ╚═╝ ██║██║██║ ╚████║╚██████╔╝
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝    ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                                                                                                   
         █████╗ ██████╗ ███████╗███████╗███╗   ██╗ █████╗ ██╗                                    
        ██╔══██╗██╔══██╗██╔════╝██╔════╝████╗  ██║██╔══██╗██║                                    
        ███████║██████╔╝███████╗█████╗  ██╔██╗ ██║███████║██║                                    
        ██╔══██║██╔══██╗╚════██║██╔══╝  ██║╚██╗██║██╔══██║██║                                    
        ██║  ██║██║  ██║███████║███████╗██║ ╚████║██║  ██║███████╗                               
        ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝                               

EOF
echo -e "${CYAN}           Ultimate Debian 13 Gaming & Productivity Platform${NC}"
echo -e "${YELLOW}                    Unleash Maximum Performance${NC}\n"

# Status message functions with enhanced styling
print_status() {
    echo -e "${BLUE}${BOLD}[●]${NC} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}${BOLD}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}${BOLD}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}${BOLD}[✗]${NC} $1"
}

print_info() {
    echo -e "${CYAN}${BOLD}[ℹ]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Administrator privileges required. Execute with: sudo $0"
    exit 1
fi

# Confirmation prompt
echo -e "${YELLOW}${BOLD}"
cat << "EOF"
This script will perform a comprehensive gaming platform installation:
• Complete KDE Plasma desktop environment with all utilities
• Advanced gaming stack (Steam, Wine, Lutris, emulators)
• GPU drivers and performance optimizations
• Multimedia codecs and productivity tools
• System-wide gaming optimizations

EOF
echo -e "${NC}"
read -p "Proceed with installation? (y/N): " -n 1 -r
echo -e "${NC}"
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Installation cancelled by user."
    exit 1
fi

print_info "Beginning comprehensive gaming platform installation..."

# System foundation update
print_status "Updating system repositories and packages..."
apt update && apt upgrade -y
apt install -y curl wget git software-properties-common apt-transport-https
print_success "System foundation updated successfully"

# Clean slate preparation
print_status "Preparing system for optimal KDE installation..."
apt purge --auto-remove -y gnome* gdm3 xfce* mate* cinnamon* lxde* 2>/dev/null || true
apt autoremove -y
print_success "System prepared for KDE installation"

# Complete KDE Plasma installation
print_status "Installing KDE Plasma desktop environment with full suite..."
apt install -y \
    task-kde-desktop \
    kde-standard \
    kde-plasma-desktop \
    plasma-workspace \
    plasma-desktop \
    kdeconnect \
    kdenlive \
    krita \
    okular \
    kate \
    dolphin \
    konsole \
    spectacle \
    gwenview \
    ark \
    kcalc \
    kcharselect \
    kcolorchooser \
    kfind \
    kruler \
    ksystemlog \
    plasma-nm \
    plasma-pa \
    bluedevil \
    powerdevil \
    systemsettings \
    discover \
    packagekit-qt5 \
    sddm \
    sddm-theme-breeze
    
# Enable SDDM display manager
systemctl enable sddm
systemctl set-default graphical.target
print_success "KDE Plasma desktop environment installed with complete utility suite"

# Core gaming platform installation
print_status "Installing comprehensive gaming ecosystem..."
apt install -y \
    steam \
    steam-installer \
    wine \
    wine64 \
    wine32 \
    winetricks \
    playonlinux \
    lutris \
    heroic \
    gamemode \
    gamemoderun \
    mesa-utils \
    vulkan-tools \
    vulkan-validationlayers \
    libvulkan1 \
    mesa-vulkan-drivers \
    firmware-amd-graphics \
    firmware-linux \
    firmware-linux-nonfree \
    libgl1-mesa-vulkan-icd \
    libvulkan1:i386 \
    mesa-vulkan-drivers:i386
print_success "Core gaming platform installed successfully"

# Emulator paradise installation
print_status "Installing comprehensive emulator collection..."
apt install -y \
    retroarch \
    libretro-* \
    pcsx2 \
    dolphin-emu \
    mupen64plus-qt \
    mame \
    ppsspp \
    desmume \
    mgba-qt \
    snes9x-gtk \
    fceux \
    mednafen \
    dosbox \
    scummvm \
    nestopia \
    visualboyadvance-gtk
print_success "Emulator collection installed successfully"

# Enable 32-bit architecture for comprehensive compatibility
print_status "Configuring 32-bit architecture support..."
dpkg --add-architecture i386
apt update
apt install -y \
    wine32 \
    libgl1-mesa-dri:i386 \
    libgl1:i386 \
    libglu1-mesa:i386 \
    mesa-utils:i386 \
    libvulkan1:i386 \
    mesa-vulkan-drivers:i386 \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6:i386 \
    libncurses5:i386 \
    libstdc++6:i386 \
    libasound2:i386 \
    libasound2-plugins:i386 \
    libpulse0:i386
print_success "32-bit architecture support configured"

# Complete multimedia codec installation
print_status "Installing comprehensive multimedia support..."
apt install -y \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-plugins-good \
    gstreamer1.0-vaapi \
    gstreamer1.0-pulseaudio \
    libavcodec-extra \
    libavcodec58 \
    libavformat58 \
    libavutil56 \
    libdvd-pkg \
    libdvdread8 \
    libdvdnav4 \
    ffmpeg \
    vlc \
    mpv \
    audacious \
    clementine
print_success "Multimedia codec suite installed"

# Configure DVD support automatically
print_status "Configuring DVD playback support..."
echo 'libdvd-pkg libdvd-pkg/build boolean true' | debconf-set-selections
echo 'libdvd-pkg libdvd-pkg/post-invoke_hook-install boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive libdvd-pkg
print_success "DVD playback support configured"

# Advanced GPU driver detection and installation
print_status "Scanning for graphics hardware..."

# NVIDIA GPU comprehensive setup
if lspci | grep -i nvidia > /dev/null; then
    print_warning "NVIDIA GPU detected - Installing complete NVIDIA stack..."
    
    # Add official NVIDIA repository
    wget -O- https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub | gpg --dearmor | tee /usr/share/keyrings/nvidia-drivers.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/nvidia-drivers.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" | tee /etc/apt/sources.list.d/nvidia-drivers.list
    
    # Add non-free repositories for Debian
    echo "deb http://deb.debian.org/debian/ trixie main contrib non-free-firmware non-free" > /etc/apt/sources.list.d/nvidia.list
    
    apt update
    apt install -y \
        nvidia-driver \
        nvidia-driver-libs \
        nvidia-driver-libs:i386 \
        nvidia-cuda-toolkit \
        nvidia-opencl-icd \
        nvidia-settings \
        nvidia-vulkan-icd \
        nvidia-vulkan-icd:i386 \
        nvidia-ml-py3 \
        libnvidia-encode1 \
        libnvidia-decode1 \
        nvidia-xconfig \
        nvidia-detect
    
    # Configure NVIDIA optimally
    nvidia-xconfig --allow-empty-initial-configuration --enable-all-gpus --separate-x-screens
    nvidia-smi -pm 1  # Enable persistence mode
    nvidia-smi -acp UNRESTRICTED  # Set application clocks policy
    
    print_success "NVIDIA GPU stack installed and optimized"
fi

# AMD GPU comprehensive setup
if lspci | grep -i "radeon\|amd" > /dev/null; then
    print_warning "AMD GPU detected - Installing complete AMD stack..."
    
    apt install -y \
        firmware-amd-graphics \
        mesa-opencl-icd \
        rocm-opencl-runtime \
        libdrm-amdgpu1 \
        xserver-xorg-video-amdgpu \
        radeontop \
        mesa-vulkan-drivers \
        mesa-vulkan-drivers:i386 \
        libvulkan1 \
        libvulkan1:i386 \
        vulkan-tools \
        mesa-utils \
        vainfo \
        libva-mesa-driver \
        mesa-va-drivers
        
    print_success "AMD GPU stack installed and optimized"
fi

# Intel GPU support
if lspci | grep -i "intel.*graphics\|intel.*display" > /dev/null; then
    print_warning "Intel GPU detected - Installing Intel graphics support..."
    
    apt install -y \
        intel-media-va-driver \
        i965-va-driver \
        mesa-va-drivers \
        vainfo \
        intel-gpu-tools \
        xserver-xorg-video-intel
        
    print_success "Intel GPU support installed"
fi

# Gaming utilities and enhancement tools
print_status "Installing advanced gaming utilities and tools..."
apt install -y \
    mangohud \
    goverlay \
    obs-studio \
    discord \
    gamemode \
    gamemoderun \
    piper \
    input-utils \
    joystick \
    evtest \
    jstest-gtk \
    antimicrox \
    qjoypad \
    xboxdrv \
    ds4drv \
    steam-devices \
    barrier \
    synergy \
    mumble \
    teamspeak3 \
    wine-binfmt \
    winetricks \
    dxvk \
    protontricks
print_success "Advanced gaming utilities installed"

# Install additional gaming frontends and tools
print_status "Installing gaming frontends and management tools..."
apt install -y \
    gamemode \
    pegasus-frontend \
    attract \
    emulationstation \
    gnome-games \
    itch \
    minigalaxy
print_success "Gaming frontends installed"

# Advanced controller and input device configuration
print_status "Configuring comprehensive input device support..."

# Load input modules
modprobe uinput
modprobe joydev
modprobe xpad

# Create and configure input groups
groupadd -f input
groupadd -f uinput
usermod -a -G input,uinput,audio,video,games $SUDO_USER

# Configure udev rules for controllers
cat > /etc/udev/rules.d/99-steam-controller-perms.rules << EOF
# Steam Controller udev rules
SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0666"
KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0666"
SUBSYSTEM=="input", ATTRS{name}=="FT260 HID UART", MODE="0666", GROUP="uinput"

# PS4/PS5 Controller
KERNEL=="hidraw*", KERNELS=="*054C:05C4*", MODE="0666"
KERNEL=="hidraw*", KERNELS=="*054C:09CC*", MODE="0666"

# Xbox Controllers
SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="028e", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02d1", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02dd", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02e3", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02ea", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="0719", MODE="0666"
EOF

udevadm control --reload-rules
udevadm trigger

print_success "Advanced input device support configured"

# Comprehensive Wine environment setup
print_status "Installing comprehensive Wine ecosystem..."
apt install -y \
    wine \
    wine64 \
    wine32 \
    winbind \
    winetricks \
    wine-binfmt \
    playonlinux \
    bottles \
    libgnutls30:i386 \
    libldap-2.5-0:i386 \
    libgpg-error0:i386 \
    libxml2:i386 \
    libasound2-plugins:i386 \
    libsdl2-2.0-0:i386 \
    libfreetype6:i386 \
    libdbus-1-3:i386 \
    libsqlite3-0:i386 \
    fonts-wine \
    libfaudio0:i386 \
    libgstreamer-plugins-base1.0-0:i386 \
    libgstreamer1.0-0:i386 \
    libnss3:i386 \
    libcapi20-3:i386 \
    libcups2:i386 \
    libfontconfig1:i386 \
    libgssapi-krb5-2:i386 \
    libjpeg62-turbo:i386 \
    libkrb5-3:i386 \
    libodbc1:i386 \
    libosmesa6:i386 \
    libpng16-16:i386 \
    libtiff5:i386 \
    libv4l-0:i386 \
    libxcomposite1:i386 \
    libxcursor1:i386 \
    libxfixes3:i386 \
    libxi6:i386 \
    libxinerama1:i386 \
    libxrandr2:i386 \
    libxrender1:i386 \
    libxxf86vm1:i386

# Install DXVK and VKD3D for DirectX support
print_status "Installing DirectX compatibility layers..."
wget -O dxvk.tar.gz https://github.com/doitsujin/dxvk/releases/latest/download/dxvk-2.4.tar.gz
tar -xzf dxvk.tar.gz
mv dxvk-* /opt/dxvk
chmod +x /opt/dxvk/setup_dxvk.sh

# Install VKD3D-Proton for DirectX 12
wget -O vkd3d-proton.tar.xz https://github.com/HansKristian-Work/vkd3d-proton/releases/latest/download/vkd3d-proton-2.13.tar.xz
tar -xJf vkd3d-proton.tar.xz
mv vkd3d-proton-* /opt/vkd3d-proton
chmod +x /opt/vkd3d-proton/setup_vkd3d_proton.sh

rm -f dxvk.tar.gz vkd3d-proton.tar.xz

print_success "Wine ecosystem with DirectX support installed"

# Advanced system optimizations for maximum gaming performance
print_status "Applying comprehensive gaming optimizations..."

# CPU governor optimization
echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils

# Gaming-optimized kernel parameters
cat >> /etc/sysctl.conf << EOF

# Gaming Performance Optimizations
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500
vm.vfs_cache_pressure=50

# Network optimizations for gaming
net.core.netdev_max_backlog=5000
net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 16384 16777216
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3

# Audio latency improvements
dev.hpet.max-user-freq=2048

# File system optimizations
fs.file-max=2097152
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF

# Configure CPU scaling
echo 'performance' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true

# Configure game-specific limits
cat >> /etc/security/limits.conf << EOF
# Gaming optimizations
@games soft nofile 1000000
@games hard nofile 1000000
@games soft nproc 1000000 
@games hard nproc 1000000
$SUDO_USER soft nofile 1000000
$SUDO_USER hard nofile 1000000
$SUDO_USER soft nproc 1000000
$SUDO_USER hard nproc 1000000
EOF

# Enable gamemode for all users
echo '@include common-session
session optional pam_systemd.so
session optional pam_ck_connector.so nox11' >> /etc/pam.d/gamemode

# Configure audio for low latency
echo 'default-sample-rate = 48000
default-sample-format = float32le
default-fragments = 2
default-fragment-size-msec = 5' >> /etc/pulse/daemon.conf

print_success "Advanced gaming optimizations applied"

# Install comprehensive monitoring and performance tools
print_status "Installing monitoring and performance analysis tools..."
apt install -y \
    htop \
    btop \
    nvtop \
    radeontop \
    intel-gpu-tools \
    iotop \
    nethogs \
    glances \
    screenfetch \
    neofetch \
    fastfetch \
    stress-ng \
    sysbench \
    benchmark \
    unigine-heaven \
    glmark2 \
    mesa-utils \
    vulkan-tools \
    clinfo \
    vainfo \
    vdpauinfo \
    cpu-x \
    hardinfo \
    i7z \
    lm-sensors \
    psensor \
    conky-all \
    gkrellm

# Configure sensors
sensors-detect --auto
print_success "Performance monitoring suite installed"

# Install additional productivity and development tools
print_status "Installing productivity and development tools..."
apt install -y \
    firefox-esr \
    thunderbird \
    libreoffice \
    gimp \
    blender \
    audacity \
    handbrake \
    brasero \
    k3b \
    cheese \
    simplescreenrecorder \
    kdenlive \
    openshot \
    pitivi \
    darktable \
    rawtherapee \
    inkscape \
    krita \
    scribus \
    code \
    sublime-text \
    vim \
    emacs \
    git \
    build-essential \
    cmake \
    python3-pip \
    nodejs \
    npm \
    flatpak \
    snapd \
    appimage-run

print_success "Productivity and development tools installed"

# Enable Flatpak and additional repositories
print_status "Configuring additional software repositories..."
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install additional gaming platforms via Flatpak
print_status "Installing additional gaming platforms..."
flatpak install -y flathub \
    com.discordapp.Discord \
    com.valvesoftware.Steam \
    net.lutris.Lutris \
    com.heroicgameslauncher.hgl \
    org.DolphinEmu.dolphin-emu \
    org.libretro.RetroArch \
    io.itch.itch \
    com.mojang.Minecraft \
    org.prismlauncher.PrismLauncher \
    com.obsproject.Studio \
    com.github.iwalton3.jellyfin-media-player

print_success "Additional gaming platforms installed via Flatpak"

# Final system optimization and cleanup
print_status "Performing final system optimization..."
apt update && apt full-upgrade -y
apt autoremove -y
apt autoclean
updatedb

# Configure firmware updates
print_status "Configuring firmware update support..."
apt install -y fwupd
fwupdmgr refresh 2>/dev/null || true

print_success "System optimization and cleanup completed"

# Create user configuration scripts
print_status "Creating user configuration scripts..."
USER_HOME=$(eval echo ~$SUDO_USER)

# Create Wine prefix setup script
cat > $USER_HOME/setup_wine.sh << 'EOF'
#!/bin/bash
# Wine Gaming Environment Setup
export WINEPREFIX=$HOME/.wine-gaming
winecfg
winetricks corefonts vcrun2019 dxvk
EOF

# Create gamemode optimization script  
cat > $USER_HOME/optimize_gaming.sh << 'EOF'
#!/bin/bash
# Gaming Session Optimizer
echo "Optimizing system for gaming..."
sudo cpupower frequency-set -g performance 2>/dev/null
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
sudo sysctl vm.swappiness=1
echo "Gaming optimizations applied!"
EOF

chmod +x $USER_HOME/setup_wine.sh $USER_HOME/optimize_gaming.sh
chown $SUDO_USER:$SUDO_USER $USER_HOME/setup_wine.sh $USER_HOME/optimize_gaming.sh

print_success "User configuration scripts created"

# Installation completion display
echo -e "${GREEN}${BOLD}"
cat << "EOF"

███████╗██╗   ██╗ ██████╗ ██████╗███████╗███████╗███████╗██╗██╗██╗
██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝██║██║██║
███████╗██║   ██║██║     ██║     █████╗  ███████╗███████╗██║██║██║
╚════██║██║   ██║██║     ██║     ██╔══╝  ╚════██║╚════██║╚═╝╚═╝╚═╝
███████║╚██████╔╝╚██████╗╚██████╗███████╗███████║███████║██╗██╗██╗
╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝╚═╝╚═╝╚═╝

    ██████╗  █████╗ ███╗   ███╗██╗███╗   ██╗ ██████╗ 
    ██╔════╝ ██╔══██╗████╗ ████║██║████╗  ██║██╔════╝ 
    ██║  ███╗███████║██╔████╔██║██║██╔██╗ ██║██║  ███╗
    ██║   ██║██╔══██║██║╚██╔╝██║██║██║╚██╗██║██║   ██║
    ╚██████╔╝██║  ██║██║ ╚═╝ ██║██║██║ ╚████║╚██████╔╝
     ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                                                       
    ██████╗ ██╗      █████╗ ████████╗███████╗ ██████╗ ██████╗ ███╗   ███╗
    ██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗████╗ ████║
    ██████╔╝██║     ███████║   ██║   █████╗  ██║   ██║██████╔╝██╔████╔██║
    ██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ██║   ██║██╔══██╗██║╚██╔╝██║
    ██║     ███████╗██║  ██║   ██║   ██║     ╚██████╔╝██║  ██║██║ ╚═╝ ██║
    ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝

EOF
echo -e "${NC}"

print_success "Nero's Gaming Arsenal installation completed successfully!"
print_info "Your system has been transformed into an ultimate gaming platform!"

echo -e "${CYAN}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "                    INSTALLATION SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"
echo -e "${YELLOW}✓ Complete KDE Plasma desktop with all utilities"
echo -e "✓ Steam, Lutris, Wine, and Heroic Games Launcher"
echo -e "✓ Comprehensive emulator collection (RetroArch, PCSX2, Dolphin, etc.)"
echo -e "✓ GPU drivers optimized (NVIDIA/AMD/Intel)"
echo -e "✓ 32-bit compatibility layer"
echo -e "✓ DirectX support via DXVK/VKD3D-Proton"
echo -e "✓ Advanced controller support"
echo -e "✓ Performance monitoring tools"
echo -e "✓ System optimizations for gaming"
echo -e "✓ Multimedia codec support"
echo -e "✓ Development and productivity tools${NC}"

echo -e "${CYAN}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "                    POST-REBOOT ACTIONS"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"
echo -e "${GREEN}1. Log into KDE Plasma desktop environment"
echo -e "2. Run: ${YELLOW}~/optimize_gaming.sh${GREEN} before gaming sessions"
echo -e "3. Setup Wine gaming prefix: ${YELLOW}~/setup_wine.sh${GREEN}"
echo -e "4. Launch Steam and enable Proton compatibility"
echo -e "5. Install games via Steam, Lutris, or Heroic"
echo -e "6. Configure RetroArch for emulation"
echo -e "7. Use MangoHUD for performance overlay: ${YELLOW}mangohud %command%${NC}"

print_warning "System reboot required in 15 seconds to apply all changes..."

# Extended countdown with system information
for i in {15..1}; do
    echo -ne "${RED}${BOLD}Rebooting in $i seconds... Press Ctrl+C to cancel\\r${NC}"
    sleep 1
done

print_status "Initiating system reboot..."
reboot