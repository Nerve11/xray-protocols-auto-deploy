#!/bin/bash
# ==================================================
# Xray Auto-Install Script (VLESS + REALITY + Vision)
# Supported: Ubuntu 20.04+, Debian 10+, CentOS 7+
# Features: Maximum stealth, XTLS Vision, uTLS fingerprinting
# TCP BBR optimization included
# ==================================================

# Configuration variables
VLESS_PORT=443
LOG_DIR="/var/log/xray"
CONFIG_DIR="/usr/local/etc/xray"

# Helper functions
Color_Off='\033[0m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BRed='\033[1;31m'
BCyan='\033[1;36m'

log_info() { echo -e "${BCyan}[INFO] $1${Color_Off}"; }
log_warn() { echo -e "${BYellow}[WARN] $1${Color_Off}"; }
log_error() { echo -e "${BRed}[ERROR] $1${Color_Off}"; exit 1; }

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
  log_error "This script must be run as root (sudo)."
fi

# Camouflage SNI selection
echo -e "${BCyan}Select camouflage website (SNI):${Color_Off}"
echo "  1 - www.microsoft.com (recommended - OCSP stapling)"
echo "  2 - dl.google.com (encrypted handshake)"
echo "  3 - www.cloudflare.com (high security)"
echo "  4 - www.apple.com (iOS/macOS devices)"
read -rp "Enter number [1/2/3/4]: " SNI_CHOICE

case "$SNI_CHOICE" in
  2)
    SNI_HOST="dl.google.com"
    DEST_PORT="443"
    ;;
  3)
    SNI_HOST="www.cloudflare.com"
    DEST_PORT="443"
    ;;
  4)
    SNI_HOST="www.apple.com"
    DEST_PORT="443"
    ;;
  *)
    SNI_HOST="www.microsoft.com"
    DEST_PORT="443"
    ;;
esac

log_info "Selected SNI: ${SNI_HOST}"

# uTLS fingerprint selection
echo -e "${BCyan}Select TLS fingerprint (browser emulation):${Color_Off}"
echo "  1 - chrome (most common, recommended)"
echo "  2 - firefox (privacy-focused)"
echo "  3 - safari (iOS/macOS)"
echo "  4 - edge (Windows)"
read -rp "Enter number [1/2/3/4]: " FP_CHOICE

case "$FP_CHOICE" in
  2)
    FINGERPRINT="firefox"
    ;;
  3)
    FINGERPRINT="safari"
    ;;
  4)
    FINGERPRINT="edge"
    ;;
  *)
    FINGERPRINT="chrome"
    ;;
esac

log_info "Selected fingerprint: ${FINGERPRINT}"

# Determine QR code path
USER_HOME=""
if [[ -n "$SUDO_USER" ]]; then
    if command -v getent &> /dev/null; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        log_warn "Command 'getent' not found."
    fi
fi

if [[ -z "$USER_HOME" ]]; then
    USER_HOME="/root"
    log_warn "Could not determine sudo user home directory. QR codes will be saved to ${USER_HOME}"
fi

QR_CODE_FILE="${USER_HOME}/vless_reality_qr.png"
mkdir -p "$(dirname "$QR_CODE_FILE")"

if [[ -n "$SUDO_USER" && -n "$USER_HOME" && "$USER_HOME" != "/root" ]]; then
    NEED_CHOWN_QR=true
else
    NEED_CHOWN_QR=false
fi

log_info "Starting VLESS + REALITY + Vision installation..."

set -eu

# OS detection and dependency installation
log_info "Detecting operating system and installing dependencies..."

if [[ ! -f /etc/os-release ]]; then
    log_error "File /etc/os-release not found. Cannot determine OS."
fi

. /etc/os-release

if [[ -z "${ID:-}" ]]; then
    log_error "Could not determine OS ID from /etc/os-release."
fi

OS="$ID"

if [[ -z "${VERSION_ID:-}" ]]; then
    log_warn "VERSION_ID not defined. Possibly rolling release."
    if [[ -n "${VERSION_CODENAME:-}" ]]; then
        VERSION_ID="${VERSION_CODENAME}"
        log_info "Using VERSION_CODENAME: ${VERSION_ID}"
    else
        VERSION_ID="unknown"
        log_warn "VERSION_ID set to 'unknown'."
    fi
fi

log_info "Detected OS: $OS ${VERSION_ID}"

log_info "Updating package list and installing dependencies..."

case $OS in
    ubuntu|debian|linuxmint|pop|neon)
        log_info "Detected Debian/Ubuntu. Installing packages..."
        apt update -y || log_error "Failed to update package list."
        apt install -y curl wget unzip socat qrencode jq coreutils bash-completion openssl || log_error "Failed to install dependencies."
        ;;
    centos|almalinux|rocky|rhel|fedora)
        log_info "Detected RHEL/CentOS. Installing packages..."
        if [[ "$OS" == "centos" ]]; then
            MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
            if [[ "$MAJOR_VERSION" == "7" ]]; then
                log_info "Installing EPEL repository for CentOS 7..."
                yum install -y epel-release || log_warn "Failed to install epel-release."
            fi
        fi
        if command -v dnf &> /dev/null; then
            dnf update -y || log_warn "Failed to update via dnf."
            dnf install -y curl wget unzip socat qrencode jq coreutils bash-completion policycoreutils-python-utils util-linux openssl || log_error "Failed to install dependencies."
        else
            yum update -y || log_warn "Failed to update via yum."
            if [[ "$OS" == "centos" ]] && [[ "${MAJOR_VERSION:-}" == "7" ]]; then
                yum install -y curl wget unzip socat qrencode jq coreutils bash-completion policycoreutils-python util-linux openssl || log_error "Failed to install dependencies."
            else
                yum install -y curl wget unzip socat qrencode jq coreutils bash-completion policycoreutils-python-utils util-linux openssl || log_error "Failed to install dependencies."
            fi
        fi
        ;;
    *)
        log_error "OS $OS is not supported. Supported: Ubuntu, Debian, CentOS, AlmaLinux, Rocky Linux."
        ;;
esac

log_info "Dependencies installed successfully."

# Enable TCP BBR
log_info "Enabling TCP BBR for network speed optimization..."

BBR_CONF="/etc/sysctl.d/99-bbr.conf"

if ! grep -q "net.core.default_qdisc=fq" "$BBR_CONF" 2>/dev/null ; then
    echo "net.core.default_qdisc=fq" | tee "$BBR_CONF" > /dev/null
fi

if ! grep -q "net.ipv4.tcp_congestion_control=bbr" "$BBR_CONF" 2>/dev/null ; then
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a "$BBR_CONF" > /dev/null
fi

if sysctl -p "$BBR_CONF"; then
    log_info "TCP BBR successfully enabled."
else
    log_warn "Failed to enable BBR. Kernel may not support it (requires 4.9+)."
fi

# Install Xray
log_info "Installing latest stable version of Xray..."

if ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install; then
    log_error "Error executing Xray installation script."
fi

if ! command -v xray &> /dev/null; then
    log_error "Command 'xray' not found after installation."
fi

log_info "Xray installed: $(xray version | head -n 1)"

# Generate UUID
USER_UUID=$(xray uuid)
if [[ -z "$USER_UUID" ]]; then
    log_error "Failed to generate UUID."
fi

log_info "Generated UUID: ${USER_UUID}"

# Generate x25519 keys
log_info "Generating x25519 key pair for REALITY..."

# Run xray x25519 and capture output
KEYS_OUTPUT=$(/usr/local/bin/xray x25519 2>&1)
if [[ -z "$KEYS_OUTPUT" ]]; then
    log_error "Failed to generate x25519 keys - no output from xray x25519."
fi

log_info "x25519 output received. Parsing keys..."

# Try multiple parsing methods
PRIVATE_KEY=""
PUBLIC_KEY=""

# Method 1: Standard format with "Private key:" and "Public key:"
if [[ -z "$PRIVATE_KEY" ]]; then
    PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep -i "Private key:" | awk '{print $3}')
fi

if [[ -z "$PUBLIC_KEY" ]]; then
    PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep -i "Public key:" | awk '{print $3}')
fi

# Method 2: Direct extraction (some versions output without labels)
if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    # Extract base64-like strings (44 characters typical for x25519)
    KEYS_ARRAY=($(echo "$KEYS_OUTPUT" | grep -oE '[A-Za-z0-9+/]{43}='))
    if [[ ${#KEYS_ARRAY[@]} -ge 2 ]]; then
        PRIVATE_KEY="${KEYS_ARRAY[0]}"
        PUBLIC_KEY="${KEYS_ARRAY[1]}"
    fi
fi

# Validate keys
if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    log_error "Failed to extract x25519 keys. Debug output:\n${KEYS_OUTPUT}"
fi

# Validate key format (should be 44 chars base64)
if [[ ${#PRIVATE_KEY} -ne 44 || ${#PUBLIC_KEY} -ne 44 ]]; then
    log_error "Invalid x25519 key format. Private: ${#PRIVATE_KEY} chars, Public: ${#PUBLIC_KEY} chars. Expected 44 each."
fi

log_info "Private key: ${PRIVATE_KEY}"
log_info "Public key: ${PUBLIC_KEY}"

# Generate shortId
SHORT_ID=$(openssl rand -hex 8)
if [[ -z "$SHORT_ID" ]]; then
    log_error "Failed to generate shortId."
fi

log_info "Generated shortId: ${SHORT_ID}"

# Configure firewall
log_info "Configuring firewall..."

if command -v ufw &> /dev/null; then
    log_info "UFW: Opening port ${VLESS_PORT}/tcp..."
    ufw allow ${VLESS_PORT}/tcp || log_warn "ufw allow command failed."
    if ufw status | grep -qw active; then
        ufw reload || log_error "Failed to reload UFW rules."
    else
        log_warn "UFW is inactive. Rules added but firewall not active. Enable with: sudo ufw enable"
    fi
elif command -v firewall-cmd &> /dev/null; then
    log_info "firewalld: Opening port ${VLESS_PORT}/tcp..."
    firewall-cmd --permanent --add-port=${VLESS_PORT}/tcp || log_warn "firewall-cmd command failed."
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload || log_error "Failed to reload firewalld rules."
    else
         log_warn "firewalld service is inactive."
    fi
    if [[ -f /usr/sbin/sestatus ]] && sestatus | grep "SELinux status:" | grep -q "enabled"; then
        log_info "SELinux detected as enabled. Configuring..."
        if command -v semanage &> /dev/null; then
            semanage port -a -t http_port_t -p tcp ${VLESS_PORT} 2>/dev/null || semanage port -m -t http_port_t -p tcp ${VLESS_PORT} || log_warn "SELinux port ${VLESS_PORT} configuration failed."
            setsebool -P httpd_can_network_connect 1 || log_warn "SELinux httpd_can_network_connect failed."
            log_info "SELinux configured."
        else
            log_warn "Command 'semanage' not found."
        fi
    fi
else
    log_warn "UFW/firewalld not found. Open port ${VLESS_PORT} manually."
fi

# Get server IP
log_info "Determining server public IP address..."

SERVER_IP=$(curl -s4 https://ipinfo.io/ip || curl -s4 https://api.ipify.org || curl -s4 https://ifconfig.me)

if [[ -z "$SERVER_IP" ]]; then
    log_error "Failed to determine public IPv4 address."
fi

log_info "Server public IP: $SERVER_IP"

# Create Xray configuration
log_info "Creating Xray configuration: ${CONFIG_DIR}/config.json..."

mkdir -p "$LOG_DIR"
chown nobody:nobody "$LOG_DIR" 2>/dev/null || chown nobody:nogroup "$LOG_DIR" 2>/dev/null || log_warn "Failed to change LOG_DIR owner."
mkdir -p "$CONFIG_DIR"

cat > "${CONFIG_DIR}/config.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log"
  },
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "https+local://8.8.8.8/dns-query",
      "localhost"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI_HOST}:${DEST_PORT}",
          "xver": 0,
          "serverNames": [
            "${SNI_HOST}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "minClientVer": "1.8.0",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "${SHORT_ID}",
            ""
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic", "fakedns"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

log_info "Xray configuration created."

# Validate Xray configuration
log_info "Validating Xray configuration..."

if ! /usr/local/bin/xray -test -config "${CONFIG_DIR}/config.json"; then
    log_error "Xray configuration contains errors."
fi

log_info "Xray configuration is valid."

# Configure and start Xray service
log_info "Configuring and restarting Xray service via systemd..."

systemctl enable xray || log_warn "Failed to enable xray service."
systemctl restart xray || log_error "Failed to restart xray service."

log_info "Waiting for service startup (3 seconds)..."
sleep 3

if ! systemctl is-active --quiet xray; then
    log_error "Xray service failed to start. Check logs: journalctl -u xray -n 50 or ${LOG_DIR}/error.log"
fi

log_info "Xray service started successfully."

# Generate VLESS link
log_info "Generating VLESS + REALITY link..."

if ! command -v jq &> /dev/null; then
    log_error "Command 'jq' not found."
fi

VLESS_LINK="vless://${USER_UUID}@${SERVER_IP}:${VLESS_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=${FINGERPRINT}&sni=${SNI_HOST}&sid=${SHORT_ID}&spx=%2F&flow=xtls-rprx-vision#VLESS-Reality-${SNI_HOST}"

QR_GENERATED=false

if command -v qrencode &> /dev/null; then
    if qrencode -o "$QR_CODE_FILE" "$VLESS_LINK"; then
        log_info "QR code saved: ${QR_CODE_FILE}"
        QR_GENERATED=true
        if [[ "$NEED_CHOWN_QR" = true ]]; then
            if command -v id &> /dev/null; then
                SUDO_USER_GROUP=$(id -gn "$SUDO_USER" 2>/dev/null)
                if [[ -n "$SUDO_USER_GROUP" ]]; then
                     chown "$SUDO_USER":"$SUDO_USER_GROUP" "$QR_CODE_FILE" || log_warn "Failed to change QR owner."
                fi
            fi
        fi
    else
        log_warn "Failed to generate QR code."
    fi
else
    log_warn "Command 'qrencode' not found. QR codes not generated."
fi

# Display summary information
log_info "=================================================="
log_info "${BGreen} VLESS + REALITY + Vision Installation Complete! ${Color_Off}"
log_info "=================================================="

echo -e "${BYellow}Server IP address:${Color_Off} ${SERVER_IP}"
echo -e "${BYellow}Port:${Color_Off} ${VLESS_PORT}"
echo -e "${BYellow}UUID:${Color_Off} ${USER_UUID}"
echo -e "${BYellow}Flow:${Color_Off} xtls-rprx-vision"
echo -e "${BYellow}Security:${Color_Off} reality"
echo -e "${BYellow}SNI:${Color_Off} ${SNI_HOST}"
echo -e "${BYellow}Fingerprint:${Color_Off} ${FINGERPRINT}"
echo -e "${BYellow}Public Key:${Color_Off} ${PUBLIC_KEY}"
echo -e "${BYellow}Short ID:${Color_Off} ${SHORT_ID}"
echo -e "${BYellow}TCP BBR:${Color_Off} enabled"
echo ""

echo -e "${BGreen}VLESS Link:${Color_Off}"
echo -e "${VLESS_LINK}"
echo ""

if [[ "$QR_GENERATED" = true ]]; then
    echo -e "${BGreen}QR Code:${Color_Off} ${QR_CODE_FILE}"
    echo -e "${BYellow}Display in terminal:${Color_Off} qrencode -t ansiutf8 \"${VLESS_LINK}\""
    echo ""
fi

echo -e "${BYellow}Client Configuration:${Color_Off}"
echo -e "  1. Use clients: v2rayN (Windows), v2rayNG (Android), Nekoray (Desktop), Happ"
echo -e "  2. Import the VLESS link or scan QR code"
echo -e "  3. Ensure client supports REALITY and XTLS Vision"
echo -e "  4. Server address: ${SERVER_IP}:${VLESS_PORT}"
echo ""

echo -e "${BCyan}--- Security Features ---${Color_Off}"
echo -e "${BGreen}✓${Color_Off} REALITY encryption (mimics ${SNI_HOST})"
echo -e "${BGreen}✓${Color_Off} XTLS Vision flow (maximum performance)"
echo -e "${BGreen}✓${Color_Off} uTLS fingerprinting (${FINGERPRINT})"
echo -e "${BGreen}✓${Color_Off} TCP BBR congestion control"
echo -e "${BGreen}✓${Color_Off} Perfect forward secrecy"
echo -e "${BGreen}✓${Color_Off} No certificate chain vulnerabilities"
echo ""

echo -e "${BCyan}--- Xray Service Management ---${Color_Off}"
echo -e "Status:    ${BYellow}systemctl status xray${Color_Off}"
echo -e "Restart:   ${BYellow}systemctl restart xray${Color_Off}"
echo -e "Stop:      ${BYellow}systemctl stop xray${Color_Off}"
echo -e "Auto-start:${BYellow}systemctl enable xray${Color_Off}"
echo ""

echo -e "${BCyan}--- Xray Logs ---${Color_Off}"
echo -e "Errors:  ${BYellow}tail -f ${LOG_DIR}/error.log${Color_Off}"
echo -e "Access:  ${BYellow}tail -f ${LOG_DIR}/access.log${Color_Off}"
echo -e "systemd: ${BYellow}journalctl -u xray --output cat -f${Color_Off}"
echo ""

echo -e "${BCyan}--- Performance Notes ---${Color_Off}"
echo -e "• REALITY provides superior stealth (indistinguishable from legitimate HTTPS)"
echo -e "• XTLS Vision offers ~1.5x speed improvement over standard proxies"
echo -e "• Recommended for heavily censored regions (China, Iran, Russia)"
echo -e "• Works with Happ, v2rayN, v2rayNG, Nekoray clients"
echo ""

log_info "Installation complete. Maximum security achieved!"

set +eu
exit 0