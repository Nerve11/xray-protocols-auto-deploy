#!/bin/bash

# ========================================
# Xray Management Utility
# Управление пользователями и настройками
# ========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

CONFIG_FILE="/usr/local/etc/xray/config.json"
INFO_FILE="/root/xray_client_info.txt"

if [[ $EUID -ne 0 ]]; then
   log_error "Этот скрипт должен быть запущен от root"
   exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Конфигурация Xray не найдена: $CONFIG_FILE"
    exit 1
fi

# ========================================
# Функции управления
# ========================================

show_status() {
    echo "═══════════════════════════════════════════"
    echo "  Статус Xray"
    echo "═══════════════════════════════════════════"
    systemctl status xray --no-pager
    echo ""
    echo "Активные соединения:"
    ss -tulpn | grep xray || echo "Нет активных соединений"
}

show_config() {
    echo "═══════════════════════════════════════════"
    echo "  Текущая конфигурация"
    echo "═══════════════════════════════════════════"
    cat $CONFIG_FILE | jq .
}

show_clients() {
    echo "═══════════════════════════════════════════"
    echo "  Список клиентов"
    echo "═══════════════════════════════════════════"
    cat $CONFIG_FILE | jq '.inbounds[0].settings.clients[]' 2>/dev/null || log_error "Ошибка чтения клиентов"
}

add_client() {
    read -p "Email нового клиента: " NEW_EMAIL
    NEW_UUID=$(uuidgen)
    
    log_info "Добавление клиента..."
    
    # Определяем flow из существующего клиента
    FLOW=$(cat $CONFIG_FILE | jq -r '.inbounds[0].settings.clients[0].flow // ""')
    
    # Создаем JSON нового клиента
    if [ -z "$FLOW" ]; then
        NEW_CLIENT='{"id":"'$NEW_UUID'","email":"'$NEW_EMAIL'"}'
    else
        NEW_CLIENT='{"id":"'$NEW_UUID'","flow":"'$FLOW'","email":"'$NEW_EMAIL'"}'
    fi
    
    # Добавляем клиента
    cat $CONFIG_FILE | jq '.inbounds[0].settings.clients += ['$NEW_CLIENT']' > /tmp/xray_config_tmp.json
    mv /tmp/xray_config_tmp.json $CONFIG_FILE
    
    systemctl restart xray
    
    log_success "Клиент добавлен:"
    echo "  Email: $NEW_EMAIL"
    echo "  UUID: $NEW_UUID"
    
    # Генерация ссылки
    generate_client_link_for_uuid "$NEW_UUID" "$NEW_EMAIL"
}

remove_client() {
    show_clients
    echo ""
    read -p "Введите email клиента для удаления: " REMOVE_EMAIL
    
    # Проверяем существование
    EXISTS=$(cat $CONFIG_FILE | jq '.inbounds[0].settings.clients[] | select(.email=="'$REMOVE_EMAIL'")' 2>/dev/null)
    
    if [ -z "$EXISTS" ]; then
        log_error "Клиент с email '$REMOVE_EMAIL' не найден"
        return
    fi
    
    # Удаляем
    cat $CONFIG_FILE | jq 'del(.inbounds[0].settings.clients[] | select(.email=="'$REMOVE_EMAIL'"))' > /tmp/xray_config_tmp.json
    mv /tmp/xray_config_tmp.json $CONFIG_FILE
    
    systemctl restart xray
    
    log_success "Клиент '$REMOVE_EMAIL' удален"
}

generate_client_link_for_uuid() {
    local UUID=$1
    local EMAIL=$2
    
    SERVER_IP=$(curl -s ifconfig.me)
    PORT=$(cat $CONFIG_FILE | jq -r '.inbounds[0].port')
    SECURITY=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.security')
    NETWORK=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.network')
    
    if [ "$SECURITY" == "reality" ]; then
        SNI=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]')
        PUBLIC_KEY=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // empty')
        SHORT_ID=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]')
        FLOW=$(cat $CONFIG_FILE | jq -r '.inbounds[0].settings.clients[0].flow // ""')
        
        if [ "$NETWORK" == "xhttp" ]; then
            PATH=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.xhttpSettings.path // "/"')
            HOST=$(cat $CONFIG_FILE | jq -r '.inbounds[0].streamSettings.xhttpSettings.host // ""')
            LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${PATH}&host=${HOST}#${EMAIL}"
        else
            LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${EMAIL}"
        fi
    else
        LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=tls&type=tcp#${EMAIL}"
    fi
    
    echo ""
    echo "Ссылка подключения:"
    echo "$LINK"
    echo ""
    echo "QR-код:"
    echo "$LINK" | qrencode -t ANSIUTF8
}

show_logs() {
    echo "═══════════════════════════════════════════"
    echo "  Логи Xray (последние 50 строк)"
    echo "═══════════════════════════════════════════"
    journalctl -u xray -n 50 --no-pager
    echo ""
    read -p "Показать логи в реальном времени? (y/n): " CHOICE
    if [ "$CHOICE" == "y" ] || [ "$CHOICE" == "Y" ]; then
        journalctl -u xray -f
    fi
}

backup_config() {
    BACKUP_DIR="/root/xray_backups"
    mkdir -p $BACKUP_DIR
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/xray_config_$TIMESTAMP.json"
    
    cp $CONFIG_FILE $BACKUP_FILE
    
    log_success "Резервная копия создана: $BACKUP_FILE"
    
    # Показываем все бэкапы
    echo ""
    echo "Все резервные копии:"
    ls -lh $BACKUP_DIR/
}

restore_config() {
    BACKUP_DIR="/root/xray_backups"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Папка с резервными копиями не найдена"
        return
    fi
    
    echo "═══════════════════════════════════════════"
    echo "  Доступные резервные копии"
    echo "═══════════════════════════════════════════"
    ls -lh $BACKUP_DIR/
    echo ""
    
    read -p "Введите имя файла для восстановления: " BACKUP_NAME
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Файл не найден: $BACKUP_FILE"
        return
    fi
    
    # Проверяем валидность JSON
    if ! jq empty $BACKUP_FILE 2>/dev/null; then
        log_error "Неверный формат JSON в файле"
        return
    fi
    
    cp $BACKUP_FILE $CONFIG_FILE
    systemctl restart xray
    
    log_success "Конфигурация восстановлена из $BACKUP_NAME"
}

change_port() {
    CURRENT_PORT=$(cat $CONFIG_FILE | jq -r '.inbounds[0].port')
    echo "Текущий порт: $CURRENT_PORT"
    read -p "Новый порт: " NEW_PORT
    
    if [ -z "$NEW_PORT" ] || ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        log_error "Неверный порт"
        return
    fi
    
    cat $CONFIG_FILE | jq '.inbounds[0].port = '$NEW_PORT > /tmp/xray_config_tmp.json
    mv /tmp/xray_config_tmp.json $CONFIG_FILE
    
    # Обновляем firewall
    if command -v ufw &> /dev/null; then
        ufw delete allow $CURRENT_PORT/tcp 2>/dev/null || true
        ufw allow $NEW_PORT/tcp
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-port=$CURRENT_PORT/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=$NEW_PORT/tcp
        firewall-cmd --reload
    fi
    
    systemctl restart xray
    
    log_success "Порт изменен на $NEW_PORT"
}

uninstall_xray() {
    echo "${RED}ВНИМАНИЕ: Это удалит Xray и все конфигурации!${NC}"
    read -p "Вы уверены? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Отменено"
        return
    fi
    
    log_info "Удаление Xray..."
    
    systemctl stop xray
    systemctl disable xray
    
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    
    rm -rf /usr/local/etc/xray/
    rm -f /root/xray_client_info.txt
    
    log_success "Xray удален"
}

# ========================================
# Меню
# ========================================

show_menu() {
    clear
    echo "═══════════════════════════════════════════"
    echo "       Xray Management Utility"
    echo "═══════════════════════════════════════════"
    echo "1)  Показать статус"
    echo "2)  Показать конфигурацию"
    echo "3)  Показать список клиентов"
    echo "4)  Добавить клиента"
    echo "5)  Удалить клиента"
    echo "6)  Показать логи"
    echo "7)  Изменить порт"
    echo "8)  Создать резервную копию"
    echo "9)  Восстановить из резервной копии"
    echo "10) Перезапустить Xray"
    echo "11) Удалить Xray"
    echo "0)  Выход"
    echo "═══════════════════════════════════════════"
    read -p "Выберите опцию: " CHOICE
    
    case $CHOICE in
        1) show_status ;;
        2) show_config ;;
        3) show_clients ;;
        4) add_client ;;
        5) remove_client ;;
        6) show_logs ;;
        7) change_port ;;
        8) backup_config ;;
        9) restore_config ;;
        10) systemctl restart xray && log_success "Xray перезапущен" ;;
        11) uninstall_xray ;;
        0) exit 0 ;;
        *) log_error "Неверный выбор" ;;
    esac
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
    show_menu
}

show_menu