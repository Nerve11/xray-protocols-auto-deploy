#!/bin/bash

# ========================================
# Xray-Core VPN Auto Installer
# Поддержка: VLESS, VLESS-Reality, XHTTP
# ========================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логирование
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка root прав
if [[ $EUID -ne 0 ]]; then
   log_error "Этот скрипт должен быть запущен от root"
   exit 1
fi

# Определение OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    log_error "Не удалось определить операционную систему"
    exit 1
fi

log_info "Обнаружена ОС: $OS $VER"

# ========================================
# Функции установки
# ========================================

install_dependencies() {
    log_info "Установка зависимостей..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y curl wget unzip jq qrencode openssl uuid-runtime >/dev/null 2>&1
            ;;
        centos|rhel|fedora|rocky|almalinux)
            yum install -y epel-release >/dev/null 2>&1
            yum install -y curl wget unzip jq qrencode openssl util-linux >/dev/null 2>&1
            ;;
        *)
            log_error "Неподдерживаемая ОС: $OS"
            exit 1
            ;;
    esac
    
    log_success "Зависимости установлены"
}

install_xray() {
    log_info "Установка Xray-core..."
    
    # Скачиваем установочный скрипт
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    # Проверяем установку
    if ! command -v xray &> /dev/null; then
        log_error "Xray не установлен"
        exit 1
    fi
    
    XRAY_VERSION=$(xray version 2>/dev/null | head -n 1)
    log_success "Xray установлен: $XRAY_VERSION"
}

enable_bbr() {
    log_info "Включение TCP BBR..."
    
    if lsmod | grep -q bbr; then
        log_warning "BBR уже включен"
        return
    fi
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    
    log_success "BBR включен"
}

# ========================================
# Генерация ключей и UUID
# ========================================

generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

generate_reality_keys() {
    xray x25519
}

generate_short_id() {
    openssl rand -hex 8
}

# ========================================
# Пользовательский ввод
# ========================================

get_user_input() {
    clear
    echo "═══════════════════════════════════════════"
    echo "  Xray VPN Auto Installer"
    echo "═══════════════════════════════════════════"
    echo ""
    
    # Протокол
    echo "Выберите протокол:"
    echo "1) VLESS"
    echo "2) VLESS + Reality"
    echo "3) VLESS + Reality + XHTTP"
    read -p "Выбор [1-3]: " PROTOCOL_CHOICE
    
    case $PROTOCOL_CHOICE in
        1) PROTOCOL="vless" ;;
        2) PROTOCOL="vless-reality" ;;
        3) PROTOCOL="vless-reality-xhttp" ;;
        *) log_error "Неверный выбор"; exit 1 ;;
    esac
    
    # UUID
    DEFAULT_UUID=$(generate_uuid)
    read -p "UUID клиента [$DEFAULT_UUID]: " USER_UUID
    USER_UUID=${USER_UUID:-$DEFAULT_UUID}
    
    # Порт
    read -p "Порт [443]: " PORT
    PORT=${PORT:-443}
    
    # SNI (для Reality)
    if [[ "$PROTOCOL" == *"reality"* ]]; then
        echo ""
        echo "Популярные SNI для Reality:"
        echo "  - www.microsoft.com"
        echo "  - www.apple.com"
        echo "  - www.cloudflare.com"
        echo "  - www.tesla.com"
        read -p "Введите SNI [www.microsoft.com]: " SNI
        SNI=${SNI:-www.microsoft.com}
        
        # Fingerprint
        echo ""
        echo "Выберите fingerprint:"
        echo "1) chrome (рекомендуется)"
        echo "2) firefox"
        echo "3) safari"
        echo "4) ios"
        echo "5) android"
        echo "6) edge"
        echo "7) random"
        read -p "Выбор [1-7]: " FP_CHOICE
        
        case $FP_CHOICE in
            1) FINGERPRINT="chrome" ;;
            2) FINGERPRINT="firefox" ;;
            3) FINGERPRINT="safari" ;;
            4) FINGERPRINT="ios" ;;
            5) FINGERPRINT="android" ;;
            6) FINGERPRINT="edge" ;;
            7) FINGERPRINT="random" ;;
            *) FINGERPRINT="chrome" ;;
        esac
        
        # Генерация Reality ключей
        log_info "Генерация Reality ключей..."
        REALITY_KEYS=$(generate_reality_keys)
        PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep "Private key:" | awk '{print $3}')
        PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep "Public key:" | awk '{print $3}')
        SHORT_ID=$(generate_short_id)
        
        log_success "Ключи сгенерированы"
    fi
    
    # Path для XHTTP
    if [[ "$PROTOCOL" == *"xhttp"* ]]; then
        read -p "XHTTP путь [/]: " XHTTP_PATH
        XHTTP_PATH=${XHTTP_PATH:-/}
    fi
    
    # Email пользователя
    read -p "Email пользователя (опционально): " USER_EMAIL
    
    echo ""
}

# ========================================
# Создание конфигураций
# ========================================

generate_vless_config() {
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "email": "${USER_EMAIL:-user@example.com}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/xray/cert.crt",
              "keyFile": "/usr/local/etc/xray/cert.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
}

generate_vless_reality_config() {
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "flow": "xtls-rprx-vision",
            "email": "${USER_EMAIL:-user@example.com}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID",
            ""
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
}

generate_vless_reality_xhttp_config() {
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$USER_UUID",
            "flow": "",
            "email": "${USER_EMAIL:-user@example.com}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID",
            ""
          ]
        },
        "xhttpSettings": {
          "path": "$XHTTP_PATH",
          "host": "$SNI"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
}

# ========================================
# Генерация клиентской ссылки
# ========================================

generate_client_link() {
    SERVER_IP=$(curl -s ifconfig.me)
    
    case $PROTOCOL in
        "vless")
            LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&security=tls&type=tcp#XrayVPN"
            ;;
        "vless-reality")
            LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#XrayReality"
            ;;
        "vless-reality-xhttp")
            LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&host=${SNI}#XrayRealityXHTTP"
            ;;
    esac
    
    echo "$LINK"
}

save_client_info() {
    local CLIENT_FILE="/root/xray_client_info.txt"
    local LINK=$(generate_client_link)
    
    cat > $CLIENT_FILE <<EOF
═══════════════════════════════════════════
         Xray VPN - Информация о клиенте
═══════════════════════════════════════════

Протокол: $PROTOCOL
Сервер: $(curl -s ifconfig.me)
Порт: $PORT
UUID: $USER_UUID
EOF

    if [[ "$PROTOCOL" == *"reality"* ]]; then
        cat >> $CLIENT_FILE <<EOF

--- Reality параметры ---
SNI: $SNI
Fingerprint: $FINGERPRINT
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
Private Key: $PRIVATE_KEY
EOF
    fi

    if [[ "$PROTOCOL" == *"xhttp"* ]]; then
        cat >> $CLIENT_FILE <<EOF

--- XHTTP параметры ---
Path: $XHTTP_PATH
Host: $SNI
EOF
    fi

    cat >> $CLIENT_FILE <<EOF

═══════════════════════════════════════════
           Ссылка для подключения:
═══════════════════════════════════════════

$LINK

═══════════════════════════════════════════
           QR-код:
═══════════════════════════════════════════

EOF

    # Генерация QR-кода в ASCII
    echo "$LINK" | qrencode -t ANSIUTF8 >> $CLIENT_FILE
    
    echo ""
    log_success "Информация сохранена в $CLIENT_FILE"
    echo ""
    cat $CLIENT_FILE
}

# ========================================
# Главная функция
# ========================================

main() {
    log_info "Запуск установки Xray VPN..."
    echo ""
    
    # Установка компонентов
    install_dependencies
    install_xray
    enable_bbr
    
    # Получение настроек от пользователя
    get_user_input
    
    # Генерация конфигурации
    log_info "Создание конфигурации..."
    case $PROTOCOL in
        "vless") generate_vless_config ;;
        "vless-reality") generate_vless_reality_config ;;
        "vless-reality-xhttp") generate_vless_reality_xhttp_config ;;
    esac
    log_success "Конфигурация создана"
    
    # Запуск и включение автозапуска
    log_info "Запуск Xray..."
    systemctl enable xray
    systemctl restart xray
    
    if systemctl is-active --quiet xray; then
        log_success "Xray запущен успешно"
    else
        log_error "Ошибка запуска Xray"
        log_info "Проверьте логи: journalctl -u xray -n 50"
        exit 1
    fi
    
    # Настройка firewall
    log_info "Настройка firewall..."
    if command -v ufw &> /dev/null; then
        ufw allow $PORT/tcp
        ufw --force enable
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --reload
    fi
    
    # Сохранение информации о клиенте
    save_client_info
    
    echo ""
    log_success "═══════════════════════════════════════════"
    log_success "  Установка завершена успешно!"
    log_success "═══════════════════════════════════════════"
    echo ""
    log_info "Управление сервисом:"
    echo "  Статус:      systemctl status xray"
    echo "  Остановка:   systemctl stop xray"
    echo "  Запуск:      systemctl start xray"
    echo "  Перезапуск:  systemctl restart xray"
    echo "  Логи:        journalctl -u xray -f"
    echo ""
    log_info "Конфигурация: /usr/local/etc/xray/config.json"
    log_info "Информация о клиенте: /root/xray_client_info.txt"
    echo ""
}

# Запуск
main