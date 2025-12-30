#!/bin/bash

# ========================================
# Xray-Core Advanced VPN Installer
# TOP-5 протоколов из Xray-examples
# ========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   log_error "Запустите скрипт от root"
   exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    log_error "Не удалось определить ОС"
    exit 1
fi

# ========================================
# Установка зависимостей
# ========================================

install_dependencies() {
    log_info "Установка зависимостей..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y curl wget unzip jq qrencode openssl uuid-runtime nginx certbot python3-certbot-nginx >/dev/null 2>&1
            ;;
        centos|rhel|fedora|rocky|almalinux)
            yum install -y epel-release >/dev/null 2>&1
            yum install -y curl wget unzip jq qrencode openssl util-linux nginx certbot python3-certbot-nginx >/dev/null 2>&1
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
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
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
# Генерация ключей
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

generate_ss_password() {
    openssl rand -base64 32
}

# ========================================
# Пользовательский ввод
# ========================================

get_user_input() {
    clear
    echo "═════════════════════════════════════════════════════════"
    echo -e "${CYAN}       Xray Advanced VPN Installer - TOP-5 Протоколы${NC}"
    echo "═════════════════════════════════════════════════════════"
    echo ""
    echo -e "${MAGENTA}Выберите протокол:${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} VLESS-TCP-XTLS-Vision-REALITY ${YELLOW}(Рекомендуется)${NC}"
    echo "   ⚡ Максимальная производительность + безопасность"
    echo "   🛡️ XTLS-Vision для обхода DPI, Reality для маскировки"
    echo ""
    echo -e "${GREEN}2)${NC} VLESS-XHTTP-Reality ${YELLOW}(Новейший)${NC}"
    echo "   🌐 Современный XHTTP транспорт"
    echo "   🚀 Отличная производительность и стабильность"
    echo ""
    echo -e "${GREEN}3)${NC} VLESS-gRPC-Reality"
    echo "   🔒 gRPC для обхода блокировок"
    echo "   🌍 Идеален для стран с жесткой цензурой"
    echo ""
    echo -e "${GREEN}4)${NC} VLESS-WebSocket-TLS"
    echo "   ☁️ Поддержка CDN (Cloudflare, etc.)"
    echo "   🌐 Классический надежный протокол"
    echo ""
    echo -e "${GREEN}5)${NC} Shadowsocks-2022"
    echo "   ⚡ Современная версия SS"
    echo "   🔒 AEAD шифрование, высокая скорость"
    echo ""
    echo "═════════════════════════════════════════════════════════"
    read -p "Выбор [1-5]: " PROTOCOL_CHOICE
    
    case $PROTOCOL_CHOICE in
        1) PROTOCOL="vless-vision-reality" ;;
        2) PROTOCOL="vless-xhttp-reality" ;;
        3) PROTOCOL="vless-grpc-reality" ;;
        4) PROTOCOL="vless-ws-tls" ;;
        5) PROTOCOL="shadowsocks-2022" ;;
        *) log_error "Неверный выбор"; exit 1 ;;
    esac
    
    # UUID
    DEFAULT_UUID=$(generate_uuid)
    read -p "UUID клиента [$DEFAULT_UUID]: " USER_UUID
    USER_UUID=${USER_UUID:-$DEFAULT_UUID}
    
    # Порт
    read -p "Порт [443]: " PORT
    PORT=${PORT:-443}
    
    # Настройки для Reality протоколов
    if [[ "$PROTOCOL" == *"reality"* ]]; then
        echo ""
        echo -e "${MAGENTA}Популярные SNI для Reality:${NC}"
        echo "  1) www.microsoft.com (рекомендуется)"
        echo "  2) www.apple.com"
        echo "  3) www.cloudflare.com"
        echo "  4) www.yahoo.com"
        echo "  5) www.amazon.com"
        echo "  6) Свой вариант"
        read -p "Выберите SNI [1-6]: " SNI_CHOICE
        
        case $SNI_CHOICE in
            1) SNI="www.microsoft.com" ;;
            2) SNI="www.apple.com" ;;
            3) SNI="www.cloudflare.com" ;;
            4) SNI="www.yahoo.com" ;;
            5) SNI="www.amazon.com" ;;
            6) read -p "Введите SNI: " SNI ;;
            *) SNI="www.microsoft.com" ;;
        esac
        
        # Fingerprint
        echo ""
        echo -e "${MAGENTA}Fingerprint браузера:${NC}"
        echo "  1) chrome (рекомендуется)"
        echo "  2) firefox"
        echo "  3) safari"
        echo "  4) ios"
        echo "  5) android"
        echo "  6) edge"
        echo "  7) random"
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
    
    # Дополнительные настройки
    if [[ "$PROTOCOL" == "vless-xhttp-reality" ]]; then
        read -p "XHTTP путь [/]: " XHTTP_PATH
        XHTTP_PATH=${XHTTP_PATH:-/}
    elif [[ "$PROTOCOL" == "vless-grpc-reality" ]]; then
        read -p "gRPC serviceName [пусто]: " GRPC_SERVICE
        GRPC_SERVICE=${GRPC_SERVICE:-}
    elif [[ "$PROTOCOL" == "vless-ws-tls" ]]; then
        read -p "Ваш домен (для SSL сертификата): " DOMAIN
        read -p "WebSocket путь [/ws]: " WS_PATH
        WS_PATH=${WS_PATH:-/ws}
    elif [[ "$PROTOCOL" == "shadowsocks-2022" ]]; then
        SS_PASSWORD=$(generate_ss_password)
        log_info "Сгенерирован пароль: $SS_PASSWORD"
        read -p "Порт для SS [8388]: " SS_PORT
        SS_PORT=${SS_PORT:-8388}
    fi
    
    # Email
    read -p "Email пользователя (опционально): " USER_EMAIL
    
    echo ""
}

# ========================================
# Генерация конфигураций
# ========================================

generate_vless_vision_reality_config() {
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
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
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
      }
    ]
  }
}
EOF
}

generate_vless_xhttp_reality_config() {
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
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
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

generate_vless_grpc_reality_config() {
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
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
        "network": "grpc",
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
            "$SHORT_ID"
          ]
        },
        "grpcSettings": {
          "serviceName": "$GRPC_SERVICE"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
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
      }
    ]
  }
}
EOF
}

generate_vless_ws_tls_config() {
    # Получение SSL сертификата
    if [ -n "$DOMAIN" ]; then
        log_info "Получение SSL сертификата для $DOMAIN..."
        certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
        CERT_FILE="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        KEY_FILE="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    else
        # Самоподписанный сертификат
        CERT_FILE="/usr/local/etc/xray/cert.crt"
        KEY_FILE="/usr/local/etc/xray/cert.key"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout $KEY_FILE -out $CERT_FILE \
            -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" 2>/dev/null
    fi
    
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
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        },
        "wsSettings": {
          "path": "$WS_PATH"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
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

generate_shadowsocks_2022_config() {
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-aes-256-gcm",
        "password": "$SS_PASSWORD",
        "network": "tcp,udp"
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
# Генерация клиентских ссылок
# ========================================

generate_client_link() {
    SERVER_IP=$(curl -s ifconfig.me)
    
    case $PROTOCOL in
        "vless-vision-reality")
            LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#XrayVisionReality"
            ;;
        "vless-xhttp-reality")
            LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&host=${SNI}#XrayXHTTPReality"
            ;;
        "vless-grpc-reality")
            LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=grpc&serviceName=${GRPC_SERVICE}#XrayGRPCReality"
            ;;
        "vless-ws-tls")
            if [ -n "$DOMAIN" ]; then
                LINK="vless://${USER_UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&type=ws&path=${WS_PATH}#XrayWebSocket"
            else
                LINK="vless://${USER_UUID}@${SERVER_IP}:${PORT}?encryption=none&security=tls&type=ws&path=${WS_PATH}#XrayWebSocket"
            fi
            ;;
        "shadowsocks-2022")
            LINK="ss://$(echo -n "2022-blake3-aes-256-gcm:$SS_PASSWORD" | base64)@${SERVER_IP}:${SS_PORT}#XraySS2022"
            ;;
    esac
    
    echo "$LINK"
}

save_client_info() {
    local CLIENT_FILE="/root/xray_client_info.txt"
    local LINK=$(generate_client_link)
    
    cat > $CLIENT_FILE <<EOF
═════════════════════════════════════════════════════════
         Xray VPN - Клиентская информация
═════════════════════════════════════════════════════════

Протокол: $PROTOCOL
Сервер: $(curl -s ifconfig.me)
EOF

    case $PROTOCOL in
        "shadowsocks-2022")
            cat >> $CLIENT_FILE <<EOF
Порт: $SS_PORT
Метод: 2022-blake3-aes-256-gcm
Пароль: $SS_PASSWORD
EOF
            ;;
        *)
            cat >> $CLIENT_FILE <<EOF
Порт: $PORT
UUID: $USER_UUID
EOF
            ;;
    esac

    if [[ "$PROTOCOL" == *"reality"* ]]; then
        cat >> $CLIENT_FILE <<EOF

--- Reality параметры ---
SNI: $SNI
Fingerprint: $FINGERPRINT
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
Private Key (сервер): $PRIVATE_KEY
EOF
    fi

    if [[ "$PROTOCOL" == *"xhttp"* ]]; then
        cat >> $CLIENT_FILE <<EOF

--- XHTTP параметры ---
Path: $XHTTP_PATH
Host: $SNI
EOF
    fi

    if [[ "$PROTOCOL" == *"grpc"* ]]; then
        cat >> $CLIENT_FILE <<EOF

--- gRPC параметры ---
Service Name: $GRPC_SERVICE
EOF
    fi

    if [[ "$PROTOCOL" == *"ws"* ]]; then
        cat >> $CLIENT_FILE <<EOF

--- WebSocket параметры ---
Path: $WS_PATH
$([ -n "$DOMAIN" ] && echo "Domain: $DOMAIN")
EOF
    fi

    cat >> $CLIENT_FILE <<EOF

═════════════════════════════════════════════════════════
           Ссылка для подключения:
═════════════════════════════════════════════════════════

$LINK

═════════════════════════════════════════════════════════
           QR-код:
═════════════════════════════════════════════════════════

EOF

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
    log_info "Запуск установки Xray Advanced VPN..."
    echo ""
    
    install_dependencies
    install_xray
    enable_bbr
    
    get_user_input
    
    log_info "Создание конфигурации..."
    case $PROTOCOL in
        "vless-vision-reality") generate_vless_vision_reality_config ;;
        "vless-xhttp-reality") generate_vless_xhttp_reality_config ;;
        "vless-grpc-reality") generate_vless_grpc_reality_config ;;
        "vless-ws-tls") generate_vless_ws_tls_config ;;
        "shadowsocks-2022") generate_shadowsocks_2022_config ;;
    esac
    log_success "Конфигурация создана"
    
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
    
    log_info "Настройка firewall..."
    if [[ "$PROTOCOL" == "shadowsocks-2022" ]]; then
        FIREWALL_PORT=$SS_PORT
    else
        FIREWALL_PORT=$PORT
    fi
    
    if command -v ufw &> /dev/null; then
        ufw allow $FIREWALL_PORT/tcp
        [ "$PROTOCOL" == "shadowsocks-2022" ] && ufw allow $FIREWALL_PORT/udp
        ufw --force enable
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$FIREWALL_PORT/tcp
        [ "$PROTOCOL" == "shadowsocks-2022" ] && firewall-cmd --permanent --add-port=$FIREWALL_PORT/udp
        firewall-cmd --reload
    fi
    
    save_client_info
    
    echo ""
    log_success "═════════════════════════════════════════════════════════"
    log_success "  Установка завершена успешно!"
    log_success "═════════════════════════════════════════════════════════"
    echo ""
    log_info "Управление:"
    echo "  systemctl status xray     - статус"
    echo "  systemctl restart xray    - перезапуск"
    echo "  journalctl -u xray -f     - логи"
    echo ""
    log_info "Файлы:"
    echo "  Конфиг: /usr/local/etc/xray/config.json"
    echo "  Клиент: /root/xray_client_info.txt"
    echo ""
}

main