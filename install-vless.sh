#!/bin/bash
# ==================================================
# Xray Auto-Install Script (VLESS + WS / VLESS + XHTTP)
# Supported: Ubuntu 20.04+, Debian 10+, CentOS 7+
# Features: No self-signed certificates, configurable SNI (google.com/yandex.ru)
# TCP BBR optimization included
# Profile Management via systemd
# ==================================================

# Configuration variables
VLESS_PORT_WS=443
VLESS_PORT_XHTTP=2053
LOG_DIR="/var/log/xray"
CONFIG_DIR="/usr/local/etc/xray"
BBR_CONF="/etc/sysctl.d/99-bbr.conf"

# Helper functions
Color_Off='\033[0m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BRed='\033[1;31m'
BCyan='\033[1;36m'
BBlue='\033[1;34m'

log_info() { echo -e "${BCyan}[INFO] $1${Color_Off}"; }
log_warn() { echo -e "${BYellow}[WARN] $1${Color_Off}"; }
log_error() { echo -e "${BRed}[ERROR] $1${Color_Off}"; exit 1; }
log_success() { echo -e "${BGreen}[SUCCESS] $1${Color_Off}"; }

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
  log_error "This script must be run as root (sudo)."
fi

# ==================================================
# PROFILE MANAGEMENT FUNCTIONS
# ==================================================

# List all profiles
list_profiles() {
    log_info "=================================================="
    log_info " Current Xray Profiles"
    log_info "=================================================="
    echo ""
    
    if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
        log_warn "Configuration file not found. Xray may not be installed."
        return 1
    fi
    
    # Extract all UUIDs from config
    PROFILE_COUNT=$(jq '.inbounds[].settings.clients | length' "${CONFIG_DIR}/config.json" 2>/dev/null | awk '{sum+=$1} END {print sum}')
    
    if [[ -z "$PROFILE_COUNT" || "$PROFILE_COUNT" == "0" ]]; then
        echo -e "${BYellow}No profiles found in configuration.${Color_Off}"
        return 1
    fi
    
    echo -e "${BGreen}Total profiles: ${PROFILE_COUNT}${Color_Off}"
    echo ""
    
    # List all UUIDs
    local counter=1
    jq -r '.inbounds[] | .protocol as $proto | .port as $port | .settings.clients[] | "\($proto):\($port):\(.id)"' "${CONFIG_DIR}/config.json" 2>/dev/null | while IFS=: read -r proto port uuid; do
        echo -e "${BBlue}[$counter]${Color_Off} Protocol: ${BCyan}${proto}${Color_Off} | Port: ${BYellow}${port}${Color_Off}"
        echo -e "    UUID: ${BGreen}${uuid}${Color_Off}"
        echo ""
        ((counter++))
    done
    
    return 0
}

# Add new profile
add_profile() {
    log_info "=================================================="
    log_info " Add New Profile"
    log_info "=================================================="
    echo ""
    
    if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
        log_error "Configuration file not found. Install Xray first."
    fi
    
    # Generate new UUID
    NEW_UUID=$(xray uuid)
    if [[ -z "$NEW_UUID" ]]; then
        log_error "Failed to generate UUID."
    fi
    
    echo -e "${BGreen}Generated new UUID:${Color_Off} ${NEW_UUID}"
    echo ""
    
    # Backup current config
    cp "${CONFIG_DIR}/config.json" "${CONFIG_DIR}/config.json.backup.$(date +%s)"
    log_info "Configuration backed up"
    
    # Add UUID to all inbounds
    jq --arg uuid "$NEW_UUID" '.inbounds[].settings.clients += [{"id": $uuid, "flow": ""}]' \
        "${CONFIG_DIR}/config.json" > "${CONFIG_DIR}/config.json.tmp"
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to update configuration"
    fi
    
    mv "${CONFIG_DIR}/config.json.tmp" "${CONFIG_DIR}/config.json"
    
    # Validate configuration
    if ! /usr/local/bin/xray -test -config "${CONFIG_DIR}/config.json" >/dev/null 2>&1; then
        log_error "Configuration validation failed. Restoring backup."
        mv "${CONFIG_DIR}/config.json.backup."* "${CONFIG_DIR}/config.json" 2>/dev/null
    fi
    
    # Restart Xray service via systemd
    log_info "Restarting Xray service..."
    systemctl restart xray || log_error "Failed to restart Xray service"
    
    sleep 2
    
    if ! systemctl is-active --quiet xray; then
        log_error "Xray service failed to start after adding profile"
    fi
    
    # Get server IP
    SERVER_IP=$(curl -s4 https://ipinfo.io/ip || curl -s4 https://api.ipify.org)
    
    # Get SNI from config
    SNI_HOST=$(jq -r '.inbounds[0].streamSettings.wsSettings.headers.Host // .inbounds[0].streamSettings.xhttpSettings.host // "google.com"' "${CONFIG_DIR}/config.json")
    
    # Generate VLESS links
    echo ""
    log_success "Profile added successfully!"
    echo ""
    echo -e "${BGreen}New UUID:${Color_Off} ${NEW_UUID}"
    echo -e "${BYellow}Server IP:${Color_Off} ${SERVER_IP}"
    echo ""
    
    # Check which protocols are configured
    HAS_WS=$(jq -r '.inbounds[] | select(.streamSettings.network == "ws") | .port' "${CONFIG_DIR}/config.json")
    HAS_XHTTP=$(jq -r '.inbounds[] | select(.streamSettings.network == "xhttp") | .port' "${CONFIG_DIR}/config.json")
    
    if [[ -n "$HAS_WS" ]]; then
        WS_PATH=$(jq -r '.inbounds[] | select(.streamSettings.network == "ws") | .streamSettings.wsSettings.path' "${CONFIG_DIR}/config.json")
        WS_PATH_ENCODED=$(printf %s "$WS_PATH" | jq -sRr @uri)
        VLESS_LINK_WS="vless://${NEW_UUID}@${SERVER_IP}:${HAS_WS}?type=ws&path=${WS_PATH_ENCODED}&host=${SNI_HOST}&security=none#VLESS-WS-${SNI_HOST}-NEW"
        
        echo -e "${BGreen}=== VLESS + WS ===${Color_Off}"
        echo -e "${VLESS_LINK_WS}"
        echo ""
    fi
    
    if [[ -n "$HAS_XHTTP" ]]; then
        VLESS_LINK_XHTTP="vless://${NEW_UUID}@${SERVER_IP}:${HAS_XHTTP}?type=xhttp&host=${SNI_HOST}&path=&security=none&mode=packet-up#VLESS-XHTTP-${SNI_HOST}-NEW"
        
        echo -e "${BGreen}=== VLESS + XHTTP ===${Color_Off}"
        echo -e "${VLESS_LINK_XHTTP}"
        echo ""
    fi
    
    log_info "Import these links in your VLESS client"
}

# Remove profile
remove_profile() {
    log_info "=================================================="
    log_info " Remove Profile"
    log_info "=================================================="
    echo ""
    
    if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
        log_error "Configuration file not found."
    fi
    
    # Show current profiles
    list_profiles
    
    if [[ $? -ne 0 ]]; then
        log_error "No profiles to remove"
    fi
    
    echo ""
    echo -e "${BYellow}Enter UUID to remove (copy-paste from list above):${Color_Off}"
    read -rp "UUID: " UUID_TO_REMOVE
    
    if [[ -z "$UUID_TO_REMOVE" ]]; then
        log_error "UUID cannot be empty"
    fi
    
    # Check if UUID exists
    UUID_EXISTS=$(jq --arg uuid "$UUID_TO_REMOVE" '.inbounds[].settings.clients[] | select(.id == $uuid) | .id' "${CONFIG_DIR}/config.json")
    
    if [[ -z "$UUID_EXISTS" ]]; then
        log_error "UUID not found in configuration"
    fi
    
    # Confirm deletion
    echo ""
    echo -e "${BRed}WARNING: This will permanently remove the profile!${Color_Off}"
    read -rp "Are you sure? (yes/no): " CONFIRM_DELETE
    
    if [[ "$CONFIRM_DELETE" != "yes" ]]; then
        log_info "Deletion cancelled"
        return 0
    fi
    
    # Backup config
    cp "${CONFIG_DIR}/config.json" "${CONFIG_DIR}/config.json.backup.$(date +%s)"
    
    # Remove UUID from all inbounds
    jq --arg uuid "$UUID_TO_REMOVE" '.inbounds[].settings.clients |= map(select(.id != $uuid))' \
        "${CONFIG_DIR}/config.json" > "${CONFIG_DIR}/config.json.tmp"
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to update configuration"
    fi
    
    mv "${CONFIG_DIR}/config.json.tmp" "${CONFIG_DIR}/config.json"
    
    # Validate configuration
    if ! /usr/local/bin/xray -test -config "${CONFIG_DIR}/config.json" >/dev/null 2>&1; then
        log_error "Configuration validation failed. Restoring backup."
        mv "${CONFIG_DIR}/config.json.backup."* "${CONFIG_DIR}/config.json" 2>/dev/null
    fi
    
    # Restart Xray service via systemd
    log_info "Restarting Xray service..."
    systemctl restart xray || log_error "Failed to restart Xray service"
    
    sleep 2
    
    if ! systemctl is-active --quiet xray; then
        log_error "Xray service failed to start after removing profile"
    fi
    
    log_success "Profile removed successfully!"
    echo -e "${BGreen}UUID ${UUID_TO_REMOVE} has been deleted${Color_Off}"
}

# ==================================================
# UNINSTALL FUNCTION
# ==================================================
uninstall_xray() {
    log_info "=================================================="
    log_info " Starting Complete Xray Removal (via systemd)"
    log_info "=================================================="
    echo ""
    
    echo -e "${BYellow}WARNING: This will completely remove Xray and all related configurations!${Color_Off}"
    echo -e "${BRed}All VPN profiles will be deleted permanently.${Color_Off}"
    echo ""
    read -rp "Are you sure you want to continue? (yes/no): " CONFIRM_UNINSTALL
    
    if [[ "$CONFIRM_UNINSTALL" != "yes" ]]; then
        log_info "Uninstallation cancelled."
        exit 0
    fi
    
    log_info "Beginning uninstallation process..."
    
    # Stop and disable Xray service via systemd
    if systemctl is-active --quiet xray; then
        log_info "Stopping Xray service via systemd..."
        systemctl stop xray || log_warn "Failed to stop xray service"
    fi
    
    if systemctl is-enabled --quiet xray 2>/dev/null; then
        log_info "Disabling Xray service via systemd..."
        systemctl disable xray || log_warn "Failed to disable xray service"
    fi
    
    # Stop and disable auto-update timer
    if systemctl is-active --quiet xray-auto-update.timer 2>/dev/null; then
        log_info "Stopping auto-update timer via systemd..."
        systemctl stop xray-auto-update.timer || log_warn "Failed to stop auto-update timer"
    fi
    
    if systemctl is-enabled --quiet xray-auto-update.timer 2>/dev/null; then
        log_info "Disabling auto-update timer via systemd..."
        systemctl disable xray-auto-update.timer || log_warn "Failed to disable auto-update timer"
    fi
    
    # Remove systemd files
    log_info "Removing systemd service files..."
    rm -f /etc/systemd/system/xray.service
    rm -f /etc/systemd/system/xray@.service
    rm -f /etc/systemd/system/xray-auto-update.service
    rm -f /etc/systemd/system/xray-auto-update.timer
    rm -f /etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf
    rm -rf /etc/systemd/system/xray.service.d
    
    systemctl daemon-reload
    
    # Remove Xray binary and scripts
    log_info "Removing Xray binaries and scripts..."
    rm -f /usr/local/bin/xray
    rm -f /usr/local/bin/xray-auto-update.sh
    rm -f /usr/bin/xray
    
    # Remove configurations
    log_info "Removing Xray configurations..."
    rm -rf "$CONFIG_DIR"
    
    # Remove logs
    log_info "Removing Xray logs..."
    rm -rf "$LOG_DIR"
    
    # Remove geoip/geosite data
    log_info "Removing geodata files..."
    rm -f /usr/local/share/xray/geoip.dat
    rm -f /usr/local/share/xray/geosite.dat
    rm -rf /usr/local/share/xray
    
    # Remove QR codes
    log_info "Removing QR code files..."
    if [[ -n "$SUDO_USER" ]]; then
        USER_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        if [[ -n "$USER_HOME" ]]; then
            rm -f "${USER_HOME}/vless_ws_qr.png"
            rm -f "${USER_HOME}/vless_xhttp_qr.png"
        fi
    fi
    rm -f /root/vless_ws_qr.png
    rm -f /root/vless_xhttp_qr.png
    
    # Firewall cleanup
    log_info "Cleaning up firewall rules..."
    
    if command -v ufw &> /dev/null; then
        log_info "Removing UFW rules for ports ${VLESS_PORT_WS} and ${VLESS_PORT_XHTTP}..."
        ufw delete allow ${VLESS_PORT_WS}/tcp 2>/dev/null || log_warn "Failed to remove UFW rule for port ${VLESS_PORT_WS}"
        ufw delete allow ${VLESS_PORT_XHTTP}/tcp 2>/dev/null || log_warn "Failed to remove UFW rule for port ${VLESS_PORT_XHTTP}"
        if ufw status | grep -qw active; then
            ufw reload || log_warn "Failed to reload UFW"
        fi
    fi
    
    if command -v firewall-cmd &> /dev/null; then
        log_info "Removing firewalld rules for ports ${VLESS_PORT_WS} and ${VLESS_PORT_XHTTP}..."
        firewall-cmd --permanent --remove-port=${VLESS_PORT_WS}/tcp 2>/dev/null || log_warn "Failed to remove firewalld rule for port ${VLESS_PORT_WS}"
        firewall-cmd --permanent --remove-port=${VLESS_PORT_XHTTP}/tcp 2>/dev/null || log_warn "Failed to remove firewalld rule for port ${VLESS_PORT_XHTTP}"
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --reload || log_warn "Failed to reload firewalld"
        fi
        
        # SELinux cleanup
        if [[ -f /usr/sbin/sestatus ]] && sestatus | grep "SELinux status:" | grep -q "enabled"; then
            if command -v semanage &> /dev/null; then
                log_info "Cleaning up SELinux port rules..."
                semanage port -d -t http_port_t -p tcp ${VLESS_PORT_WS} 2>/dev/null || log_warn "SELinux cleanup for port ${VLESS_PORT_WS} failed"
                semanage port -d -t http_port_t -p tcp ${VLESS_PORT_XHTTP} 2>/dev/null || log_warn "SELinux cleanup for port ${VLESS_PORT_XHTTP} failed"
            fi
        fi
    fi
    
    # BBR cleanup option
    echo ""
    echo -e "${BYellow}Do you want to remove TCP BBR configuration?${Color_Off}"
    echo "This will restore default TCP congestion control."
    read -rp "Remove BBR settings? (yes/no): " REMOVE_BBR
    
    if [[ "$REMOVE_BBR" == "yes" ]]; then
        log_info "Removing BBR configuration..."
        rm -f "$BBR_CONF"
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || log_warn "Failed to reset TCP congestion control"
        sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || log_warn "Failed to reset default qdisc"
        log_success "BBR configuration removed"
    else
        log_info "Keeping BBR configuration"
    fi
    
    echo ""
    log_success "=================================================="
    log_success " Xray Completely Removed via systemd"
    log_success "=================================================="
    echo -e "${BGreen}All Xray components have been removed:${Color_Off}"
    echo -e "  ${BGreen}✓${Color_Off} Service stopped and disabled via systemd"
    echo -e "  ${BGreen}✓${Color_Off} Binaries deleted"
    echo -e "  ${BGreen}✓${Color_Off} Configurations removed"
    echo -e "  ${BGreen}✓${Color_Off} Logs cleared"
    echo -e "  ${BGreen}✓${Color_Off} Firewall rules cleaned"
    if [[ "$REMOVE_BBR" == "yes" ]]; then
        echo -e "  ${BGreen}✓${Color_Off} BBR configuration removed"
    fi
    echo ""
    log_info "Server is clean. You can now reinstall or use for other purposes."
    exit 0
}

# ==================================================
# MAIN MENU
# ==================================================
show_main_menu() {
    echo -e "${BCyan}=================================================="
    echo -e " Xray VLESS Manager (systemd integration)"
    echo -e "==================================================${Color_Off}"
    echo ""
    echo "Select action:"
    echo "  ${BGreen}1${Color_Off} - Install Xray (VLESS + WS / XHTTP)"
    echo "  ${BYellow}2${Color_Off} - Manage Profiles (add/remove users)"
    echo "  ${BRed}3${Color_Off} - Complete Removal (uninstall Xray)"
    echo "  ${BCyan}4${Color_Off} - Show Service Status (systemd)"
    echo "  ${BBlue}5${Color_Off} - Exit"
    echo ""
    read -rp "Enter number [1-5]: " MAIN_CHOICE
    echo ""
}

# Profile management submenu
show_profile_menu() {
    while true; do
        echo -e "${BCyan}=================================================="
        echo -e " Profile Management"
        echo -e "==================================================${Color_Off}"
        echo ""
        echo "Select action:"
        echo "  ${BGreen}1${Color_Off} - List all profiles"
        echo "  ${BYellow}2${Color_Off} - Add new profile (UUID)"
        echo "  ${BRed}3${Color_Off} - Remove profile (UUID)"
        echo "  ${BBlue}4${Color_Off} - Back to main menu"
        echo ""
        read -rp "Enter number [1-4]: " PROFILE_CHOICE
        echo ""
        
        case "$PROFILE_CHOICE" in
            1)
                list_profiles
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                add_profile
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                remove_profile
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                return 0
                ;;
            *)
                log_warn "Invalid choice. Try again."
                ;;
        esac
    done
}

# Show systemd service status
show_service_status() {
    log_info "=================================================="
    log_info " Xray Service Status (systemd)"
    log_info "=================================================="
    echo ""
    
    if systemctl list-unit-files | grep -q "^xray.service"; then
        systemctl status xray --no-pager -l
        echo ""
        echo -e "${BCyan}--- Auto-update Timer Status ---${Color_Off}"
        if systemctl list-unit-files | grep -q "^xray-auto-update.timer"; then
            systemctl status xray-auto-update.timer --no-pager -l
        else
            echo -e "${BYellow}Auto-update timer not configured${Color_Off}"
        fi
    else
        log_warn "Xray service not found. Install Xray first."
    fi
    
    echo ""
}

# Main menu loop
while true; do
    show_main_menu
    
    case "$MAIN_CHOICE" in
        1)
            log_info "Starting installation..."
            break
            ;;
        2)
            show_profile_menu
            ;;
        3)
            uninstall_xray
            ;;
        4)
            show_service_status
            read -rp "Press Enter to continue..."
            ;;
        5)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_warn "Invalid choice. Try again."
            ;;
    esac
done

# ==================================================
# INSTALLATION PROCESS
# ==================================================

# Installation mode: ws, xhttp or both
INSTALL_MODE="ws" # default WS
WS_PATH="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"

# Auto-update selection
echo -e "${BCyan}Enable automatic Xray updates?${Color_Off}"
echo "  1 - Yes (check for updates every 2 days and auto-install)"
echo "  2 - No (manual updates only)"
read -rp "Enter number [1/2]: " AUTO_UPDATE_CHOICE

case "$AUTO_UPDATE_CHOICE" in
  1)
    ENABLE_AUTO_UPDATE=true
    log_info "Auto-update will be enabled"
    ;;
  *)
    ENABLE_AUTO_UPDATE=false
    log_info "Auto-update disabled. Update manually when needed."
    ;;
esac

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

# Setup auto-update if enabled
if [[ "$ENABLE_AUTO_UPDATE" = true ]]; then
    log_info "Setting up automatic updates via systemd..."
    
    # Download auto-update script
    if wget -O /usr/local/bin/xray-auto-update.sh \
        https://raw.githubusercontent.com/Nerve11/Xray-Vless-auto-Deploy/main/xray-auto-update.sh; then
        chmod +x /usr/local/bin/xray-auto-update.sh
        log_info "Auto-update script installed"
    else
        log_warn "Failed to download auto-update script. Skipping auto-update setup."
        ENABLE_AUTO_UPDATE=false
    fi
    
    if [[ "$ENABLE_AUTO_UPDATE" = true ]]; then
        # Download systemd service
        if wget -O /etc/systemd/system/xray-auto-update.service \
            https://raw.githubusercontent.com/Nerve11/Xray-Vless-auto-Deploy/main/systemd/xray-auto-update.service; then
            log_info "Auto-update service installed"
        else
            log_warn "Failed to download service file"
            ENABLE_AUTO_UPDATE=false
        fi
    fi
    
    if [[ "$ENABLE_AUTO_UPDATE" = true ]]; then
        # Download systemd timer
        if wget -O /etc/systemd/system/xray-auto-update.timer \
            https://raw.githubusercontent.com/Nerve11/Xray-Vless-auto-Deploy/main/systemd/xray-auto-update.timer; then
            log_info "Auto-update timer installed"
        else
            log_warn "Failed to download timer file"
            ENABLE_AUTO_UPDATE=false
        fi
    fi
    
    if [[ "$ENABLE_AUTO_UPDATE" = true ]]; then
        # Enable and start timer
        systemctl daemon-reload
        systemctl enable xray-auto-update.timer
        systemctl start xray-auto-update.timer
        log_info "Auto-update enabled via systemd. Xray will check for updates every 2 days."
    fi
fi

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
          "mode": "packet-up",
          "host": "${SNI_HOST}",
          "path": "",
          "extra": {
            "xPaddingBytes": "10-50"
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
          "mode": "packet-up",
          "host": "${SNI_HOST}",
          "path": "",
          "extra": {
            "xPaddingBytes": "10-50"
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

log_info "Xray service started successfully via systemd."

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
VLESS_LINK_XHTTP="vless://${USER_UUID}@${SERVER_IP}:${VLESS_PORT_XHTTP}?type=xhttp&host=${SNI_HOST}&path=&security=none&mode=packet-up#VLESS-XHTTP-${SNI_HOST}"

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
if [[ "$ENABLE_AUTO_UPDATE" = true ]]; then
    echo -e "${BYellow}Auto-update:${Color_Off} enabled via systemd (checks every 2 days)"
fi
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
  echo -e "${BYellow}Mode:${Color_Off} packet-up (bidirectional)"
  echo -e "${BYellow}Padding:${Color_Off} 10-50 bytes (anti-DPI)"
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
  echo -e "${BYellow}Mode:${Color_Off} packet-up (bidirectional)"
  echo -e "${BYellow}Padding:${Color_Off} 10-50 bytes (anti-DPI)"
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
if [[ "$INSTALL_MODE" == "xhttp" || "$INSTALL_MODE" == "both" ]]; then
  echo -e "  5. XHTTP requires Xray-core based client (v2rayNG, Nekoray with xray-core)"
fi
echo ""

echo -e "${BCyan}--- Xray Service Management (systemd) ---${Color_Off}"
echo -e "Status:       ${BYellow}systemctl status xray${Color_Off}"
echo -e "Restart:      ${BYellow}systemctl restart xray${Color_Off}"
echo -e "Stop:         ${BYellow}systemctl stop xray${Color_Off}"
echo -e "Auto-start:   ${BYellow}systemctl enable xray${Color_Off}"
echo -e "View logs:    ${BYellow}journalctl -u xray -f${Color_Off}"
echo ""

echo -e "${BCyan}--- Profile Management ---${Color_Off}"
echo -e "Run script again: ${BYellow}sudo bash install-vless.sh${Color_Off}"
echo -e "Select option 2 for profile management"
echo ""

if [[ "$ENABLE_AUTO_UPDATE" = true ]]; then
    echo -e "${BCyan}--- Auto-Update Management (systemd) ---${Color_Off}"
    echo -e "Check status: ${BYellow}systemctl status xray-auto-update.timer${Color_Off}"
    echo -e "View log:     ${BYellow}tail -f /var/log/xray/auto-update.log${Color_Off}"
    echo -e "Disable:      ${BYellow}systemctl stop xray-auto-update.timer && systemctl disable xray-auto-update.timer${Color_Off}"
    echo ""
fi

echo -e "${BCyan}--- Complete Removal ---${Color_Off}"
echo -e "Uninstall: ${BYellow}sudo bash install-vless.sh${Color_Off} → Select option 3"
echo ""

echo -e "${BCyan}--- Xray Logs ---${Color_Off}"
echo -e "Errors:  ${BYellow}tail -f ${LOG_DIR}/error.log${Color_Off}"
echo -e "Access:  ${BYellow}tail -f ${LOG_DIR}/access.log${Color_Off}"
echo -e "systemd: ${BYellow}journalctl -u xray --output cat -f${Color_Off}"
echo ""

log_info "Installation complete. Stay secure!"

set +eu
exit 0