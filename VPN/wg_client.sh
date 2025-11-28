#!/usr/bin/env bash
# ==============================================================================
#  WireGuard Client Install – one-click connection
#  Works on any apt-based Linux (Debian, Ubuntu, Raspbian, …)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

WG_IFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENT_KEYDIR="${WG_DIR}/client"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'

log()   { echo -e "${BLUE}[*]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[✔]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }
err()   { echo -e "${RED}[✘]${NC} $*" >&2; }

banner() {
    cat <<'EOF'

   _____ _ _            _   __        __   _
  / ____| (_)          | |  \ \      / /__(_)_ __
 | |    | |_  ___ _ __ | |_  \ \ /\ / / _ \ | '__|
 | |    | | |/ _ \ '_ \| __|  \ V  V /  __/ | |
 | |____| | |  __/ | | | |_    \_/\_/ \___|_|_|
  \_____|_|_|\___|_| |_|\__|   WireGuard Client

EOF
}

die() { err "$*"; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "Run with sudo"; }

detect_os() {
    command -v apt-get &>/dev/null || die "Only apt-based distros supported"
    PKG_MGR="apt-get"
}

install_wg() {
    command -v wg &>/dev/null && { ok "WireGuard already installed"; return; }
    log "Installing WireGuard..."
    $PKG_MGR update -qq
    $PKG_MGR install -y wireguard wireguard-tools || die "Install failed"
    ok "WireGuard installed"
}

ensure_dir() { mkdir -p "$CLIENT_KEYDIR"; chmod 700 "$CLIENT_KEYDIR"; }

gen_keypair() {
    [[ -f "${CLIENT_KEYDIR}/private.key" ]] && return
    log "Generating client key pair..."
    wg genkey | tee "${CLIENT_KEYDIR}/private.key" | wg pubkey > "${CLIENT_KEYDIR}/public.key"
    chmod 600 "${CLIENT_KEYDIR}/private.key"
    ok "Keys ready"
}

pubkey() { cat "${CLIENT_KEYDIR}/public.key"; }

ask() {
    local prompt="$1" var="$2" default="${3:-}"
    while :; do
        read -p "$(log "$prompt")" val
        val=${val:-$default}
        [[ -z "$val" ]] || break
        warn "Cannot be empty"
    done
    eval "$var='$val'"
}

valid_ip() { [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && return 0 || return 1; }

write_client_cfg() {
    local cfg="${WG_DIR}/${WG_IFACE}.conf"
    cat > "$cfg" <<EOF
[Interface]
PrivateKey = $(cat "${CLIENT_KEYDIR}/private.key")
Address = ${CLIENT_IP}/24
$( [[ -n "${DNS:-}" ]] && echo "DNS = $DNS" )

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_EP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    chmod 600 "$cfg"
    ok "Config written to $cfg"
}

start_service() {
    systemctl enable wg-quick@${WG_IFACE} >/dev/null
    systemctl restart wg-quick@${WG_IFACE} || die "Failed to start wg-quick"
    ok "WireGuard client is ACTIVE"
}

main() {
    banner
    need_root
    detect_os
    install_wg
    ensure_dir
    gen_keypair

    echo "========================================"
    echo " YOUR PUBLIC KEY (send to server admin):"
    echo " $(pubkey)"
    echo "========================================"
    echo

    ask "Server public key (44 chars): " SERVER_PUB
    [[ ${#SERVER_PUB} -eq 44 ]] || die "Invalid server public key"

    ask "Server public IP or hostname: " SERVER_HOST
    ask "Server port (default 51820): " SERVER_PORT 51820

    ask "Your assigned client IP (e.g. 10.0.0.5): " CLIENT_IP
    valid_ip "$CLIENT_IP" || die "Bad IP"

    ask "DNS server (optional, press Enter for none): " DNS ""

    SERVER_EP="${SERVER_HOST}"

    write_client_cfg
    start_service

    echo
    ok "All done! Connection status:"
    wg show "$WG_IFACE"
}

main