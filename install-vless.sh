#!/bin/bash
# ==================================================
# Xray Auto-Install Script (VLESS + WS / VLESS + XHTTP)
# Supported: Ubuntu 20.04+, Debian 10+, CentOS 7+
# Features: No self-signed certificates, configurable SNI (google.com/yandex.ru)
# TCP BBR optimization included
# ==================================================

# Installation mode: ws, xhttp or both
INSTALL_MODE="ws" # default WS

# Configuration variables
VLESS_PORT_WS=443
VLESS_PORT_XHTTP=2053
WS_PATH="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
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

# SNI selection
echo -e "${BCyan}Select SNI for masking:${Color_Off}"
echo "  1 - google.com (recommended)"
echo "  2 - yandex.ru"
read -rp "Enter number [1/2]: " SNI_CHOICE

case "$SNI_CHOICE" in
  2)
    SNI_HOST="yandex.ru"
    ;;
  *)
    SNI_HOST="google.com"
    ;;
esac

log_info "Selected SNI: ${SNI_HOST}"

# Installation mode selection
echo -e "${BCyan}Select installation mode:${Color_Off}"
echo "  1 - VLESS + WS (port 443, SNI ${SNI_HOST})"
echo "  2 - VLESS + XHTTP (port 2053, SNI ${SNI_HOST})"
echo "  3 - BOTH MODES (ports 443 and 2053, shared UUID)"
read -rp "Enter number [1/2/3]: " MODE_CHOICE

case "$MODE_CHOICE" in
  2)
    INSTALL_MODE="xhttp"
    log_info "Selected mode: VLESS + XHTTP (port ${VLESS_PORT_XHTTP}, SNI ${SNI_HOST})"
    ;;
  3)
    INSTALL_MODE="both"
    log_info "Selected mode: VLESS + WS + XHTTP (ports ${VLESS_PORT_WS} and ${VLESS_PORT_XHTTP}, SNI ${SNI_HOST})"
    ;;
  *)
    INSTALL_MODE="ws"
    log_info "Selected mode: VLESS + WS (port ${VLESS_PORT_WS}, SNI ${SNI_HOST})"
    ;;
esac

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

QR_CODE_FILE_WS="${USER_HOME}/vless_ws_qr.png"
QR_CODE_FILE_XHTTP="${USER_HOME}/vless_xhttp_qr.png"
mkdir -p "$(dirname "$QR_CODE_FILE_WS")"

if [[ -n "$SUDO_USER" && -n "$USER_HOME" && "$USER_HOME" != "/root" ]]; then
    NEED_CHOWN_QR=true
else
    NEED_CHOWN_QR=false
fi

log_info "Starting VLESS VPN installation script (Xray)..."
log_info "Mode: ${INSTALL_MODE}"

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
        apt install -y curl wget unzip socat qrencode jq coreutils bash-completion || log_error "Failed to install dependencies."
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
            dnf install -y curl wget unzip socat qrencode jq coreutils bash-completion policycoreutils-python-utils util-linux || log_error "Failed to install dependencies."
        else
            yum update -y || log_warn "Failed to update via yum."
            if [[ "$OS" == "centos" ]] && [[ "${MAJOR_VERSION:-}" == "7" ]]; then
                yum install -y curl wget unzip socat qrencode jq coreutils bash-completion policycoreutils-python util-linux || log_error "Failed to install dependencies."
            else
                yum install -y curl wget unzip socat qrencode jq coreutils bash-completion policycoreutils-python-utils util-linux || log_error "Failed to install dependencies."
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

# Configure firewall
log_info "Configuring firewall..."

if [[ "$INSTALL_MODE" == "both" ]]; then
  PORTS_TO_OPEN="${VLESS_PORT_WS} ${VLESS_PORT_XHTTP}"
else
  if [[ "$INSTALL_MODE" == "ws" ]]; then
    PORTS_TO_OPEN="${VLESS_PORT_WS}"
  else
    PORTS_TO_OPEN="${VLESS_PORT_XHTTP}"
  fi
fi

if command -v ufw &> /dev/null; then
    for PORT in $PORTS_TO_OPEN; do
      log_info "UFW: Opening port ${PORT}/tcp..."
      ufw allow ${PORT}/tcp || log_warn "ufw allow command failed."
    done
    if ufw status | grep -qw active; then
        ufw reload || log_error "Failed to reload UFW rules."
    else
        log_warn "UFW is inactive. Rules added but firewall not active. Enable with: sudo ufw enable"
    fi
elif command -v firewall-cmd &> /dev/null; then
    for PORT in $PORTS_TO_OPEN; do
      log_info "firewalld: Opening port ${PORT}/tcp..."
      firewall-cmd --permanent --add-port=${PORT}/tcp || log_warn "firewall-cmd command failed."
    done
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload || log_error "Failed to reload firewalld rules."
    else
         log_warn "firewalld service is inactive."
    fi
    if [[ -f /usr/sbin/sestatus ]] && sestatus | grep "SELinux status:" | grep -q "enabled"; then
        log_info "SELinux detected as enabled. Configuring..."
        if command -v semanage &> /dev/null; then
            for PORT in $PORTS_TO_OPEN; do
              semanage port -a -t http_port_t -p tcp ${PORT} 2>/dev/null || semanage port -m -t http_port_t -p tcp ${PORT} || log_warn "SELinux port ${PORT} configuration failed."
            done
            setsebool -P httpd_can_network_connect 1 || log_warn "SELinux httpd_can_network_connect failed."
            log_info "SELinux configured."
        else
            log_warn "Command 'semanage' not found."
        fi
    fi
else
    log_warn "UFW/firewalld not found. Open ports manually: $PORTS_TO_OPEN"
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

if [[ "$INSTALL_MODE" == "ws" ]]; then
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
      "port": ${VLESS_PORT_WS},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${WS_PATH}",
          "headers": {
            "Host": "${SNI_HOST}"
          }
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
elif [[ "$INSTALL_MODE" == "xhttp" ]]; then
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
      "port": ${VLESS_PORT_XHTTP},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "mode": "stream-one",
          "host": "${SNI_HOST}",
          "path": "/"
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
else
  # Both mode: two inbounds
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
      "port": ${VLESS_PORT_WS},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${WS_PATH}",
          "headers": {
            "Host": "${SNI_HOST}"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic", "fakedns"]
      }
    },
    {
      "port": ${VLESS_PORT_XHTTP},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "mode": "stream-one",
          "host": "${SNI_HOST}",
          "path": "/"
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
fi

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

# Generate VLESS links and QR codes
log_info "Generating VLESS links and QR codes..."

if ! command -v jq &> /dev/null; then
    log_error "Command 'jq' not found."
fi

WS_PATH_ENCODED=$(printf %s "$WS_PATH" | jq -sRr @uri)

if [[ -z "$WS_PATH_ENCODED" ]]; then
    log_error "Failed to URL-encode WS path."
fi

VLESS_LINK_WS="vless://${USER_UUID}@${SERVER_IP}:${VLESS_PORT_WS}?type=ws&path=${WS_PATH_ENCODED}&host=${SNI_HOST}&security=none#VLESS-WS-${SNI_HOST}"
VLESS_LINK_XHTTP="vless://${USER_UUID}@${SERVER_IP}:${VLESS_PORT_XHTTP}?type=xhttp&host=${SNI_HOST}&path=%2F&security=none#VLESS-XHTTP-${SNI_HOST}"

QR_WS_GENERATED=false
QR_XHTTP_GENERATED=false

if command -v qrencode &> /dev/null; then
    if [[ "$INSTALL_MODE" == "ws" || "$INSTALL_MODE" == "both" ]]; then
      if qrencode -o "$QR_CODE_FILE_WS" "$VLESS_LINK_WS"; then
          log_info "WS QR code saved: ${QR_CODE_FILE_WS}"
          QR_WS_GENERATED=true
          if [[ "$NEED_CHOWN_QR" = true ]]; then
            if command -v id &> /dev/null; then
                SUDO_USER_GROUP=$(id -gn "$SUDO_USER" 2>/dev/null)
                if [[ -n "$SUDO_USER_GROUP" ]]; then
                     chown "$SUDO_USER":"$SUDO_USER_GROUP" "$QR_CODE_FILE_WS" || log_warn "Failed to change QR_WS owner."
                fi
            fi
          fi
      else
          log_warn "Failed to generate WS QR code."
      fi
    fi

    if [[ "$INSTALL_MODE" == "xhttp" || "$INSTALL_MODE" == "both" ]]; then
      if qrencode -o "$QR_CODE_FILE_XHTTP" "$VLESS_LINK_XHTTP"; then
          log_info "XHTTP QR code saved: ${QR_CODE_FILE_XHTTP}"
          QR_XHTTP_GENERATED=true
          if [[ "$NEED_CHOWN_QR" = true ]]; then
            if command -v id &> /dev/null; then
                SUDO_USER_GROUP=$(id -gn "$SUDO_USER" 2>/dev/null)
                if [[ -n "$SUDO_USER_GROUP" ]]; then
                     chown "$SUDO_USER":"$SUDO_USER_GROUP" "$QR_CODE_FILE_XHTTP" || log_warn "Failed to change QR_XHTTP owner."
                fi
            fi
          fi
      else
          log_warn "Failed to generate XHTTP QR code."
      fi
    fi
else
    log_warn "Command 'qrencode' not found. QR codes not generated."
fi

# Display summary information
log_info "=================================================="
log_info "${BGreen} VLESS VPN Installation Complete! ${Color_Off}"
log_info "=================================================="

echo -e "${BYellow}Server IP address:${Color_Off} ${SERVER_IP}"
echo -e "${BYellow}UUID (shared):${Color_Off} ${USER_UUID}"
echo -e "${BYellow}SNI/Host:${Color_Off} ${SNI_HOST}"
echo -e "${BYellow}Security:${Color_Off} none (no TLS)"
echo -e "${BYellow}TCP BBR:${Color_Off} enabled"
echo ""

if [[ "$INSTALL_MODE" == "ws" ]]; then
  echo -e "${BGreen}=== VLESS + WS ===${Color_Off}"
  echo -e "${BYellow}Port:${Color_Off} ${VLESS_PORT_WS}"
  echo -e "${BYellow}WS Path:${Color_Off} ${WS_PATH}"
  echo ""
  echo -e "${BGreen}VLESS Link:${Color_Off}"
  echo -e "${VLESS_LINK_WS}"
  echo ""
  if [[ "$QR_WS_GENERATED" = true ]]; then
      echo -e "${BGreen}QR Code:${Color_Off} ${QR_CODE_FILE_WS}"
      echo -e "${BYellow}Display in terminal:${Color_Off} qrencode -t ansiutf8 \"${VLESS_LINK_WS}\""
      echo ""
  fi
elif [[ "$INSTALL_MODE" == "xhttp" ]]; then
  echo -e "${BGreen}=== VLESS + XHTTP ===${Color_Off}"
  echo -e "${BYellow}Port:${Color_Off} ${VLESS_PORT_XHTTP}"
  echo ""
  echo -e "${BGreen}VLESS Link:${Color_Off}"
  echo -e "${VLESS_LINK_XHTTP}"
  echo ""
  if [[ "$QR_XHTTP_GENERATED" = true ]]; then
      echo -e "${BGreen}QR Code:${Color_Off} ${QR_CODE_FILE_XHTTP}"
      echo -e "${BYellow}Display in terminal:${Color_Off} qrencode -t ansiutf8 \"${VLESS_LINK_XHTTP}\""
      echo ""
  fi
else
  echo -e "${BGreen}=== VLESS + WS (Port ${VLESS_PORT_WS}) ===${Color_Off}"
  echo -e "${BYellow}WS Path:${Color_Off} ${WS_PATH}"
  echo ""
  echo -e "${BGreen}WS Link:${Color_Off}"
  echo -e "${VLESS_LINK_WS}"
  echo ""
  if [[ "$QR_WS_GENERATED" = true ]]; then
      echo -e "${BGreen}WS QR Code:${Color_Off} ${QR_CODE_FILE_WS}"
      echo -e "${BYellow}Display in terminal:${Color_Off} qrencode -t ansiutf8 \"${VLESS_LINK_WS}\""
      echo ""
  fi

  echo -e "${BGreen}=== VLESS + XHTTP (Port ${VLESS_PORT_XHTTP}) ===${Color_Off}"
  echo ""
  echo -e "${BGreen}XHTTP Link:${Color_Off}"
  echo -e "${VLESS_LINK_XHTTP}"
  echo ""
  if [[ "$QR_XHTTP_GENERATED" = true ]]; then
      echo -e "${BGreen}XHTTP QR Code:${Color_Off} ${QR_CODE_FILE_XHTTP}"
      echo -e "${BYellow}Display in terminal:${Color_Off} qrencode -t ansiutf8 \"${VLESS_LINK_XHTTP}\""
      echo ""
  fi
fi

echo -e "${BYellow}Client Configuration:${Color_Off}"
echo -e "  1. Import the link or QR code into your VLESS client"
echo -e "  2. Verify Host/SNI: ${BRed}${SNI_HOST}${Color_Off}"
echo -e "  3. Security mode: ${BRed}none${Color_Off} (no TLS/certificates)"
echo -e "  4. Server address: ${SERVER_IP}"
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

log_info "Installation complete. Stay secure!"

set +eu
exit 0