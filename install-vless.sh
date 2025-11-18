#!/bin/bash
# ==================================================
# Скрипт автоматической установки Xray (VLESS + WS + TLS)
# Ориентирован на: Ubuntu 20.04+, Debian 10+, CentOS 7+
# Особенности: Самоподписанный сертификат (подключение по IP), порт 8443, QR-код.
# Включает автоматическое включение TCP BBR для оптимизации скорости.
# ==================================================

# Конфигурационные переменные
VLESS_PORT=8443
WS_PATH="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
LOG_DIR="/var/log/xray"
CONFIG_DIR="/usr/local/etc/xray"
CERT_DIR="/usr/local/etc/xray/certs"
CERT_FILE="${CERT_DIR}/server.crt"
KEY_FILE="${CERT_DIR}/server.key"

# Вспомогательные функции
Color_Off='\033[0m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BRed='\033[1;31m'
BCyan='\033[1;36m'

log_info() { echo -e "${BCyan}[INFO] $1${Color_Off}"; }
log_warn() { echo -e "${BYellow}[WARN] $1${Color_Off}"; }
log_error() { echo -e "${BRed}[ERROR] $1${Color_Off}"; exit 1; }

# Проверка прав суперпользователя
if [[ "$EUID" -ne 0 ]]; then
  log_error "Этот скрипт необходимо запускать с правами root (sudo)."
fi

# Определение пути для QR-кода
USER_HOME=""
if [[ -n "$SUDO_USER" ]]; then
    if command -v getent &> /dev/null; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        log_warn "Команда 'getent' не найдена."
    fi
fi

if [[ -z "$USER_HOME" ]]; then
    USER_HOME="/root"
    log_warn "Не удалось определить домашний каталог пользователя sudo или getent не найден. QR-код будет сохранен в ${USER_HOME}"
fi

QR_CODE_FILE="${USER_HOME}/vless_qr.png"
mkdir -p "$(dirname "$QR_CODE_FILE")"

if [[ -n "$SUDO_USER" && -n "$USER_HOME" && "$USER_HOME" != "/root" ]]; then
    NEED_CHOWN_QR=true
else
    NEED_CHOWN_QR=false
fi

# Начало выполнения скрипта
log_info "Запуск скрипта установки VLESS VPN на базе Xray..."
log_info "Выбран порт: ${VLESS_PORT}"
log_info "QR-код будет сохранен в: ${QR_CODE_FILE}"

set -eu # Прерывание при ошибках и неопределенных переменных

# Определение ОС и установка зависимостей
log_info "Определение операционной системы и установка зависимостей..."

if [[ ! -f /etc/os-release ]]; then
    log_error "Файл /etc/os-release не найден. Не удалось определить операционную систему."
fi

# Чтение переменных из /etc/os-release
. /etc/os-release

# Проверка обязательной переменной ID
if [[ -z "${ID:-}" ]]; then
    log_error "Не удалось определить ID операционной системы в /etc/os-release."
fi

OS="$ID"

# Для VERSION_ID (может отсутствовать в Debian testing/sid, Ubuntu rolling)
if [[ -z "${VERSION_ID:-}" ]]; then
    log_warn "VERSION_ID не определен в /etc/os-release. Возможно, вы используете rolling release или testing версию."
    # Для Debian testing/sid используем VERSION_CODENAME или устанавливаем дефолтное значение
    if [[ -n "${VERSION_CODENAME:-}" ]]; then
        VERSION_ID="${VERSION_CODENAME}"
        log_info "Используется VERSION_CODENAME: ${VERSION_ID}"
    else
        VERSION_ID="unknown"
        log_warn "VERSION_ID установлен в 'unknown'. Продолжаем с базовыми проверками."
    fi
else
    VERSION_ID="${VERSION_ID}"
fi

log_info "Обнаружена ОС: $OS ${VERSION_ID}"

# Установка зависимостей в зависимости от ОС
log_info "Обновление списка пакетов и установка зависимостей..."

case $OS in
    ubuntu|debian|linuxmint|pop|neon)
        log_info "Обнаружен Debian/Ubuntu-based дистрибутив. Установка пакетов..."
        apt update -y || log_error "Не удалось обновить список пакетов."
        apt install -y curl wget unzip socat qrencode jq coreutils openssl bash-completion || log_error "Не удалось установить зависимости."
        ;;
    centos|almalinux|rocky|rhel|fedora)
        log_info "Обнаружен RHEL/CentOS-based дистрибутив. Установка пакетов..."
        
        # Для CentOS 7 добавляем EPEL репозиторий
        if [[ "$OS" == "centos" ]]; then
            # Определяем мажорную версию
            MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
            if [[ "$MAJOR_VERSION" == "7" ]]; then
                log_info "Установка репозитория EPEL для CentOS 7..."
                yum install -y epel-release || log_warn "Не удалось установить epel-release."
            fi
        fi
        
        # Для RHEL 8+ и его клонов используем dnf, если доступен
        if command -v dnf &> /dev/null; then
            log_info "Используется dnf для установки пакетов..."
            dnf update -y || log_warn "Не удалось обновить систему через dnf."
            dnf install -y curl wget unzip socat qrencode jq coreutils openssl bash-completion policycoreutils-python-utils util-linux || log_error "Не удалось установить зависимости через dnf."
        else
            log_info "Используется yum для установки пакетов..."
            yum update -y || log_warn "Не удалось обновить систему через yum."
            # Для CentOS 7 используем policycoreutils-python вместо policycoreutils-python-utils
            if [[ "$OS" == "centos" ]] && [[ "${MAJOR_VERSION:-}" == "7" ]]; then
                yum install -y curl wget unzip socat qrencode jq coreutils openssl bash-completion policycoreutils-python util-linux || log_error "Не удалось установить зависимости через yum."
            else
                yum install -y curl wget unzip socat qrencode jq coreutils openssl bash-completion policycoreutils-python-utils util-linux || log_error "Не удалось установить зависимости через yum."
            fi
        fi
        ;;
    *)
        log_error "Операционная система $OS не поддерживается этим скриптом. Поддерживаются: Ubuntu, Debian, CentOS, AlmaLinux, Rocky Linux."
        ;;
esac

log_info "Зависимости успешно установлены."

# Включение TCP BBR (для оптимизации скорости)
log_info "Включение TCP BBR для оптимизации скорости сети..."

BBR_CONF="/etc/sysctl.d/99-bbr.conf"

# Проверяем, есть ли уже файл и содержит ли он нужные строки (простая проверка)
if ! grep -q "net.core.default_qdisc=fq" "$BBR_CONF" 2>/dev/null ; then
    echo "net.core.default_qdisc=fq" | tee "$BBR_CONF" > /dev/null
fi

if ! grep -q "net.ipv4.tcp_congestion_control=bbr" "$BBR_CONF" 2>/dev/null ; then
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a "$BBR_CONF" > /dev/null
fi

# Применяем настройки из файла
log_info "Применение настроек sysctl для BBR..."
if sysctl -p "$BBR_CONF"; then
    log_info "Настройки TCP BBR успешно применены."
else
    log_warn "Не удалось применить настройки sysctl из $BBR_CONF. Возможно, BBR не поддерживается ядром вашей системы (требуется ядро 4.9+)."
fi

# Установка Xray
log_info "Установка последней стабильной версии Xray..."

if ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install; then
    log_error "Ошибка при выполнении скрипта установки Xray."
fi

if ! command -v xray &> /dev/null; then
    log_error "Команда 'xray' не найдена после установки."
fi

log_info "Xray успешно установлен: $(xray version | head -n 1)"

# Генерация UUID
USER_UUID=$(xray uuid)
if [[ -z "$USER_UUID" ]]; then
    log_error "Не удалось сгенерировать UUID с помощью 'xray uuid'."
fi

log_info "Сгенерирован UUID пользователя: ${USER_UUID}"

# Настройка Firewall
log_info "Настройка брандмауэра для порта ${VLESS_PORT}/tcp..."

if command -v ufw &> /dev/null; then
    log_info "Обнаружен UFW. Открытие порта ${VLESS_PORT}/tcp..."
    ufw allow ${VLESS_PORT}/tcp || log_warn "Команда 'ufw allow' завершилась с ошибкой."
    
    if ufw status | grep -qw active; then
        ufw reload || log_error "Не удалось перезагрузить правила UFW."
    else
        log_warn "UFW не активен (inactive). Правило добавлено, но firewall не работает. Активируйте его командой 'sudo ufw enable', если нужно."
    fi
    
    log_info "Порт ${VLESS_PORT}/tcp настроен в UFW."

elif command -v firewall-cmd &> /dev/null; then
    log_info "Обнаружен firewalld. Открытие порта ${VLESS_PORT}/tcp..."
    firewall-cmd --permanent --add-port=${VLESS_PORT}/tcp || log_warn "Команда 'firewall-cmd --add-port' завершилась с ошибкой."
    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload || log_error "Не удалось перезагрузить правила firewalld."
    else
         log_warn "Служба firewalld не активна. Правило добавлено, но firewall не работает."
    fi
    
    log_info "Порт ${VLESS_PORT}/tcp настроен в firewalld."
    
    # Настройка SELinux для RHEL/CentOS
    if [[ -f /usr/sbin/sestatus ]] && sestatus | grep "SELinux status:" | grep -q "enabled"; then
        log_info "Обнаружен включенный SELinux. Настройка для порта ${VLESS_PORT}..."
        
        if command -v semanage &> /dev/null; then
            semanage port -a -t http_port_t -p tcp ${VLESS_PORT} 2>/dev/null || semanage port -m -t http_port_t -p tcp ${VLESS_PORT} || log_warn "Не удалось добавить правило SELinux для порта ${VLESS_PORT}."
            setsebool -P httpd_can_network_connect 1 || log_warn "Не удалось установить булево значение httpd_can_network_connect в SELinux."
            log_info "SELinux настроен для порта ${VLESS_PORT}."
        else
            log_warn "Команда 'semanage' не найдена. Пропускаем настройку SELinux."
        fi
    fi
else
    log_warn "Не удалось обнаружить UFW или firewalld. Убедитесь, что порт ${VLESS_PORT}/tcp открыт вручную."
fi

# Генерация самоподписанного сертификата TLS
log_info "Генерация самоподписанного TLS сертификата..."

SERVER_IP=$(curl -s4 https://ipinfo.io/ip || curl -s4 https://api.ipify.org || curl -s4 https://ifconfig.me)

if [[ -z "$SERVER_IP" ]]; then
    log_error "Не удалось автоматически определить публичный IPv4-адрес сервера."
fi

log_info "Публичный IP-адрес сервера: $SERVER_IP"

mkdir -p "$CERT_DIR"

log_info "Создание ключа ${KEY_FILE} и сертификата ${CERT_FILE}..."

if ! openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 3650 \
    -subj "/CN=${SERVER_IP}" \
    -addext "subjectAltName = IP:${SERVER_IP}"; then
    log_error "Ошибка при генерации TLS сертификата с помощью openssl."
fi

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
    log_error "Файлы TLS сертификата (${CERT_FILE}) или ключа (${KEY_FILE}) не найдены после генерации."
fi

log_info "TLS сертификат успешно сгенерирован для IP: $SERVER_IP"

chmod 644 "$CERT_FILE"
chgrp nobody "$KEY_FILE" 2>/dev/null || chgrp nogroup "$KEY_FILE" 2>/dev/null || log_warn "Не удалось изменить группу файла ключа ${KEY_FILE}."
chmod 640 "$KEY_FILE"

log_info "Установлены права доступа к файлам сертификата (Сертификат: 644, Ключ: 640)."

# Создание конфигурационного файла Xray
log_info "Создание конфигурационного файла Xray: ${CONFIG_DIR}/config.json"

mkdir -p "$LOG_DIR"
chown nobody:nobody "$LOG_DIR" 2>/dev/null || chown nobody:nogroup "$LOG_DIR" 2>/dev/null || log_warn "Не удалось изменить владельца ${LOG_DIR}."

cat > "${CONFIG_DIR}/config.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log"
  },
  "dns": {
    "servers": [
      "https://1.1.1.1/dns-query",
      "https://8.8.8.8/dns-query",
      "https://9.9.9.9/dns-query",
      "1.1.1.1",
      "8.8.8.8",
      "9.9.9.9",
      "localhost"
    ],
    "queryStrategy": "UseIP"
  },
  "inbounds": [
    {
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${USER_UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["http/1.1"],
          "minVersion": "1.3",
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        },
        "wsSettings": {
          "path": "${WS_PATH}",
          "headers": {
            "Host": "${SERVER_IP}"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "fakedns"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
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
        "port": 53,
        "network": "udp",
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

log_info "Конфигурационный файл Xray создан."

# Проверка конфигурации Xray
log_info "Проверка конфигурации Xray..."

if ! /usr/local/bin/xray -test -config "${CONFIG_DIR}/config.json"; then
    log_error "Конфигурация Xray (${CONFIG_DIR}/config.json) содержит ошибки."
fi

log_info "Конфигурация Xray корректна."

# Настройка и запуск службы Xray
log_info "Настройка и перезапуск службы Xray через systemd..."

systemctl enable xray || log_warn "Не удалось включить автозапуск службы Xray."
systemctl restart xray || log_error "Не удалось перезапустить службу Xray."

log_info "Ожидание запуска службы Xray (3 секунды)..."
sleep 3

if ! systemctl is-active --quiet xray; then
    log_error "Служба Xray не запустилась. Проверьте логи: journalctl -u xray -n 50 --no-pager или ${LOG_DIR}/error.log"
fi

log_info "Служба Xray успешно запущена и работает."

# Генерация VLESS ссылки и QR-кода
log_info "Генерация VLESS ссылки и QR-кода..."

if ! command -v jq &> /dev/null; then
    log_error "Команда 'jq' не найдена."
fi

WS_PATH_ENCODED=$(printf %s "$WS_PATH" | jq -sRr @uri)

if [[ -z "$WS_PATH_ENCODED" ]]; then
    log_error "Не удалось URL-кодировать путь WebSocket."
fi

VLESS_LINK="vless://${USER_UUID}@${SERVER_IP}:${VLESS_PORT}?type=ws&path=${WS_PATH_ENCODED}&security=tls&sni=${SERVER_IP}&allowInsecure=1#VLESS-WS-TLS-${SERVER_IP}"

QR_CODE_GENERATED=false

if command -v qrencode &> /dev/null; then
    if qrencode -o "$QR_CODE_FILE" "$VLESS_LINK"; then
        log_info "QR-код сохранен в файл: ${QR_CODE_FILE}"
        QR_CODE_GENERATED=true
        
        if [[ "$NEED_CHOWN_QR" = true ]]; then
            if command -v id &> /dev/null; then
                SUDO_USER_GROUP=$(id -gn "$SUDO_USER" 2>/dev/null)
                if [[ -n "$SUDO_USER_GROUP" ]]; then
                     chown "$SUDO_USER":"$SUDO_USER_GROUP" "$QR_CODE_FILE" || log_warn "Не удалось изменить владельца файла QR-кода (${QR_CODE_FILE})."
                else
                     log_warn "Не удалось определить группу для пользователя $SUDO_USER."
                fi
            else
                log_warn "Команда 'id' не найдена. Невозможно изменить владельца QR-кода."
            fi
        fi
    else
        log_warn "Не удалось сгенерировать QR-код в ${QR_CODE_FILE}."
    fi
else
    log_warn "Команда 'qrencode' не найдена. QR-код не сгенерирован."
fi

# Вывод итоговой информации
log_info "=================================================="
log_info "${BGreen} Установка VLESS VPN завершена! ${Color_Off}"
log_info "=================================================="
echo -e "${BYellow}IP-адрес сервера:${Color_Off} ${SERVER_IP}"
echo -e "${BYellow}Порт:${Color_Off} ${VLESS_PORT}"
echo -e "${BYellow}UUID:${Color_Off} ${USER_UUID}"
echo -e "${BYellow}Транспорт:${Color_Off} WebSocket (ws)"
echo -e "${BYellow}Путь WebSocket:${Color_Off} ${WS_PATH}"
echo -e "${BYellow}Шифрование:${Color_Off} TLS 1.3 (самоподписанный сертификат)"
echo -e "${BYellow}TCP Ускорение:${Color_Off} BBR включен (рекомендуется)"
echo ""
echo -e "${BGreen}Ваша VLESS ссылка (скопируйте целиком):${Color_Off}"
echo -e "${VLESS_LINK}"
echo ""

if [[ "$QR_CODE_GENERATED" = true ]]; then
    echo -e "${BGreen}QR-код для импорта конфигурации сохранен в:${Color_Off} ${QR_CODE_FILE}"
    echo -e "${BYellow}Вы можете отобразить QR-код в консоли (если поддерживается UTF-8) командой:${Color_Off}"
    echo -e "  qrencode -t ansiutf8 \"${VLESS_LINK}\""
    echo ""
else
    echo -e "${BYellow}QR-код не был сгенерирован.${Color_Off}"
    echo ""
fi

echo -e "${BYellow}ВАЖНО - Настройка клиента:${Color_Off}"
echo -e "  1. Импортируйте ссылку или QR-код в ваш клиент."
echo -e "  2. ${BRed}ОБЯЗАТЕЛЬНО${Color_Off} включите опцию '${BRed}Разрешить небезопасное соединение${Color_Off}'"
echo -e "     (Allow Insecure / skip cert verify / tlsAllowInsecure=1 и т.п.) в настройках TLS/Security."
echo -e "  3. Убедитесь, что в поле SNI (Server Name Indication), Server Address, или Host указан IP-адрес сервера:"
echo -e "     ${BRed}${SERVER_IP}${Color_Off}"
echo ""
echo -e "${BCyan}--- Управление службой Xray ---${Color_Off}"
echo -e "Проверить статус:    ${BYellow}systemctl status xray${Color_Off}"
echo -e "Перезапустить:       ${BYellow}systemctl restart xray${Color_Off}"
echo -e "Остановить:          ${BYellow}systemctl stop xray${Color_Off}"
echo -e "Включить автозапуск: ${BYellow}systemctl enable xray${Color_Off}"
echo -e "Выключить автозапуск:${BYellow}systemctl disable xray${Color_Off}"
echo ""
echo -e "${BCyan}--- Просмотр логов Xray ---${Color_Off}"
echo -e "Лог ошибок (warning/error):  ${BYellow}tail -f ${LOG_DIR}/error.log${Color_Off}"
echo -e "Лог доступа (если включен):  ${BYellow}tail -f ${LOG_DIR}/access.log${Color_Off}"
echo -e "Полный лог службы (systemd): ${BYellow}journalctl -u xray --output cat -f${Color_Off}"
echo ""
echo -e "${BCyan}--- Дополнительная оптимизация ---${Color_Off}"
echo -e "Для дальнейшей оптимизации скорости/задержки вы можете отредактировать файл ${CONFIG_DIR}/config.json"
echo -e "и настроить параметры в секции 'policy', например, 'bufferSize'. Требуется тестирование."
echo ""

log_info "Установка завершена. Приятного использования!"

set +eu # Возвращаем нормальное поведение
exit 0
