#!/usr/bin/env bash
# ==============================================================================
#  WireGuard Server Setup – --install | --connect
#  Works on any apt-based Linux (Debian, Ubuntu, Raspbian, …)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# --------------------------  CONFIG & COLORS  ---------------------------------
WG_IFACE="wg0"
WG_PORT="51820"
WG_DIR="/etc/wireguard"
SERVER_KEYDIR="${WG_DIR}/server"
CLIENTS_DIR="${WG_DIR}/clients"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'

log()   { echo -e "${BLUE}[*]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[✔]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }
err()   { echo -e "${RED}[✘]${NC} $*" >&2; }

banner() {
    cat <<'EOF'

   __        __   _                            _ 
   \ \      / /__(_)_ __   __ _  ___ _ __   __| |
    \ \ /\ / / _ \ | '_ \ / _` |/ _ \ '_ \ / _` |
     \ V  V /  __/ | | | | (_| |  __/ | | | (_| |
      \_/\_/ \___|_|_| |_|\__, |\___|_| |_|\__,_|
                           |___/                  

EOF
}

# --------------------------  HELPERS  ----------------------------------------
die() { err "$*"; exit 1; }

need_root() {
    [[ $EUID -eq 0 ]] || die "Run with sudo"
}

detect_os() {
    if command -v apt-get >/dev/null; then
        PKG_MGR="apt-get"
        return 0
    fi
    die "Only apt-based distros are supported (Debian/Ubuntu/Raspbian)."
}

install_wg() {
    if command -v wg &>/dev/null; then
        ok "WireGuard already installed"
        return
    fi
    log "Updating package list..."
    $PKG_MGR update -qq
    log "Installing WireGuard..."
    $PKG_MGR install -y wireguard wireguard-tools || die "Failed to install WireGuard"
    ok "WireGuard installed"
}

ensure_dirs() {
    mkdir -p "$SERVER_KEYDIR" "$CLIENTS_DIR"
    chmod 700 "$SERVER_KEYDIR" "$CLIENTS_DIR"
}

gen_keypair() {
    local dir=$1
    local priv="${dir}/private.key"
    local pub="${dir}/public.key"

    [[ -f "$priv" ]] && { ok "Keys already exist in $dir"; return; }

    log "Generating key pair in $dir ..."
    wg genkey | tee "$priv" | wg pubkey > "$pub"
    chmod 600 "$priv"
    chmod 644 "$pub"
    ok "Key pair created"
}

pubkey() { cat "$1/public.key"; }

# --------------------------  SERVER INSTALL  ---------------------------------
server_install() {
    log "=== SERVER INSTALL MODE ==="
    ensure_dirs
    gen_keypair "$SERVER_KEYDIR"

    read -p "$(log 'Server listening IP (e.g. 10.0.0.1): ')" srv_ip
    srv_ip=${srv_ip:-10.0.0.1}
    [[ $srv_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid IP"

    read -p "$(log 'External interface for NAT (e.g. eth0): ')" nat_if
    nat_if=${nat_if:-eth0}

    local cfg="${WG_DIR}/${WG_IFACE}.conf"
    cat > "$cfg" <<EOF
[Interface]
PrivateKey = $(cat "${SERVER_KEYDIR}/private.key")
Address = ${srv_ip}/24
ListenPort = ${WG_PORT}
PostUp = iptables -A FORWARD -i ${WG_IFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${nat_if} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${nat_if} -j MASQUERADE
EOF
    chmod 600 "$cfg"
    ok "Server config written to $cfg"

    # IP forwarding
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sed -i '/net.ipv4.ip_forward/s/^#//' /etc/sysctl.conf
    ok "IP forwarding enabled"

    # Enable on boot
    systemctl enable wg-quick@${WG_IFACE} >/dev/null
    systemctl restart wg-quick@${WG_IFACE} || die "Failed to start wg-quick"

    ok "WireGuard server is UP!"
    echo
    echo "========================================"
    echo " SERVER PUBLIC KEY (give to clients):"
    echo " $(pubkey "$SERVER_KEYDIR")"
    echo "========================================"
    echo
    log "To add a client later:  sudo $0 --connect"
}

# --------------------------  SERVER CONNECT (add client) --------------------
server_connect() {
    log "=== ADD CLIENT MODE ==="
    [[ -f "${SERVER_KEYDIR}/public.key" ]] || die "Server keys not found – run --install first"

    echo "Server public key:"
    echo " $(pubkey "$SERVER_KEYDIR")"
    echo

    read -p "Client name (alphanumeric): " cname
    [[ $cname =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid client name"
    local cdir="${CLIENTS_DIR}/${cname}"
    mkdir -p "$cdir"
    chmod 700 "$cdir"

    read -p "Client public key (44 chars): " cpub
    [[ ${#cpub} -eq 44 ]] || die "Invalid public key length"

    read -p "Client IP (e.g. 10.0.0.5): " cip
    [[ $cip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid IP"

    # Save client key for reference
    echo "$cpub" > "${cdir}/public.key"
    echo "$cip"  > "${cdir}/ip"

    # Add peer to live interface
    wg set "${WG_IFACE}" peer "$cpub" allowed-ips "${cip}/32" || die "wg set failed"
    ok "Client $cname added (IP $cip)"

    # Persist in config
    {
        echo
        echo "# === Client: $cname ==="
        echo "[Peer]"
        echo "PublicKey = $cpub"
        echo "AllowedIPs = ${cip}/32"
    } >> "${WG_DIR}/${WG_IFACE}.conf"

    # Generate client config snippet
    cat > "${cdir}/client.conf" <<EOF
[Interface]
PrivateKey = <INSERT CLIENT PRIVATE KEY HERE>
Address = ${cip}/24
DNS = 1.1.1.1   # optional

[Peer]
PublicKey = $(pubkey "$SERVER_KEYDIR")
Endpoint = $(curl -s ifconfig.me):${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    ok "Client config saved to ${cdir}/client.conf"
    echo "Give the file above to the client (replace PrivateKey)."
}

# --------------------------  MAIN  -------------------------------------------
main() {
    banner
    need_root
    detect_os
    install_wg

    case "${1:-}" in
        --install) server_install ;;
        --connect) server_connect ;;
        -h|--help)
            echo "Usage: sudo $0 [--install | --connect]"
            exit 0
            ;;
        *) die "Missing argument. Use --install or --connect" ;;
    esac
}

main "$@"