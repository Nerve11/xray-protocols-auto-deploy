# Xray Auto-Deploy with Web Dashboard

[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.109+-green.svg)](https://fastapi.tiangolo.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Production-ready автоматический установщик Xray VPN с веб-интерфейсом для управления профилями.**

## 🎯 Ключевые возможности

### Поддерживаемые протоколы
- **VLESS + WebSocket** — универсальная совместимость, порт 443
- **VLESS + XHTTP** — низкая задержка, порт 2053 (требует xray-core клиенты)
- **VLESS + REALITY + Vision** — максимальная стелс-защита (рекомендуется для Китая/Ирана)
- **VMess + WebSocket** — legacy-поддержка старых клиентов
- **Trojan + XTLS** — TLS-маскировка веб-трафика

### Web Dashboard
- ✅ **CRUD профилей** через REST API
- ✅ **Генерация QR-кодов** для мобильных клиентов
- ✅ **Live статистика** соединений и трафика
- ✅ **Backup/Restore** конфигураций
- ✅ **Multi-protocol** поддержка в одном интерфейсе

### Системные требования
- **OS**: Ubuntu 20.04+, Debian 10+, CentOS 7+, AlmaLinux 8+, Rocky Linux 8+
- **RAM**: 1GB минимум (2GB рекомендуется)
- **Python**: 3.11+ (устанавливается автоматически)
- **Xray**: Latest stable (устанавливается автоматически)

---

## 🚀 Быстрый старт

### Одной командой
```bash
curl -fsSL https://raw.githubusercontent.com/Nerve11/Xray-Vless-auto-Deploy/feature/dashboard-mvp/install-dashboard.sh | sudo bash
```

### Или вручную
```bash
# Скачать установщик
wget https://raw.githubusercontent.com/Nerve11/Xray-Vless-auto-Deploy/feature/dashboard-mvp/install-dashboard.sh

# Сделать исполняемым
chmod +x install-dashboard.sh

# Запустить с sudo
sudo ./install-dashboard.sh
```

### Интерактивное меню
```
================================================
 Xray Multi-Protocol Installer + Dashboard
================================================

Select protocol configuration:
  1 - VLESS + WebSocket (universal, port 443)
  2 - VLESS + XHTTP (low latency, port 2053)
  3 - VLESS + REALITY + Vision (maximum stealth)
  4 - VMess + WebSocket (legacy support)
  5 - Trojan + XTLS (TLS masquerading)

Enable Web Dashboard? [Y/n]: y
Dashboard port [8080]: 
```

---

## 📊 Использование Dashboard

### Доступ
После установки dashboard доступен по адресу:
```
http://YOUR_SERVER_IP:8080
```

### API Endpoints

#### Список профилей
```bash
curl http://localhost:8080/api/profiles
```

#### Создание профиля
```bash
curl -X POST "http://localhost:8080/api/profiles?email=user@example.com"
```

#### Удаление профиля
```bash
curl -X DELETE http://localhost:8080/api/profiles/{UUID}
```

#### Получение QR-кода
```bash
curl http://localhost:8080/api/profiles/{UUID}/qr --output qr.png
```

#### Статистика
```bash
curl http://localhost:8080/api/stats
```

---

## 🏗️ Архитектура проекта

```
Xray-Vless-auto-Deploy/
├── install-dashboard.sh          # Master installer
├── backend/
│   ├── main.py                   # FastAPI application
│   ├── models.py                 # Pydantic models
│   ├── config_manager.py         # Xray config operations
│   ├── protocol_templates/       # JSON templates per protocol
│   │   ├── vless_ws.json
│   │   ├── vless_xhttp.json
│   │   ├── vless_reality.json
│   │   ├── vmess_ws.json
│   │   └── trojan_xtls.json
│   └── requirements.txt
├── frontend/
│   ├── index.html                # Main UI
│   └── assets/
│       ├── app.js                # Frontend logic
│       └── styles.css            # Custom styles
├── systemd/
│   ├── xray-dashboard.service    # Dashboard systemd unit
│   └── xray.service.override     # Xray service overrides
├── scripts/
│   ├── backup-config.sh          # Backup utility
│   └── migrate-users.sh          # User migration tool
└── tests/
    ├── test_api.py               # API tests
    └── test_protocols.py         # Protocol validation tests
```

---

## 🔧 Расширенная конфигурация

### Смена протокола после установки
```bash
sudo /opt/xray-dashboard/scripts/switch-protocol.sh
```

### Добавление кастомного протокола
1. Создать JSON-шаблон в `backend/protocol_templates/`
2. Добавить валидацию в `backend/models.py`
3. Обновить UI в `frontend/index.html`

### Настройка SSL для Dashboard
```bash
# Использовать Nginx reverse proxy
sudo apt install nginx certbot python3-certbot-nginx
sudo certbot --nginx -d dashboard.yourdomain.com
```

Пример конфига Nginx:
```nginx
server {
    listen 443 ssl http2;
    server_name dashboard.yourdomain.com;
    
    ssl_certificate /etc/letsencrypt/live/dashboard.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dashboard.yourdomain.com/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 🔒 Безопасность

### Настройки по умолчанию
- Dashboard доступен **только по IP** (без авторизации в MVP)
- Рекомендуется использовать **firewall whitelist**:
  ```bash
  sudo ufw allow from YOUR_ADMIN_IP to any port 8080
  ```

### Production Hardening
1. **Включить JWT авторизацию** (см. `backend/auth.py.example`)
2. **Rate limiting** через `slowapi`
3. **HTTPS обязательно** (reverse proxy + Let's Encrypt)
4. **Регулярные бэкапы**:
   ```bash
   # Cron job для ежедневного бэкапа
   0 3 * * * /opt/xray-dashboard/scripts/backup-config.sh
   ```

---

## 🧪 Тестирование

```bash
# Установка dev-зависимостей
pip install -r backend/requirements-dev.txt

# Запуск тестов
pytest tests/ -v

# Валидация конфигов
python -m backend.config_manager validate
```

---

## 📈 Мониторинг

### Логи
```bash
# Dashboard logs
sudo journalctl -u xray-dashboard -f

# Xray logs
sudo tail -f /var/log/xray/access.log
sudo tail -f /var/log/xray/error.log
```

### Prometheus Metrics (опционально)
```bash
# Endpoint для Prometheus scraping
curl http://localhost:8080/metrics
```

---

## 🛠️ Управление сервисами

```bash
# Dashboard
sudo systemctl status xray-dashboard
sudo systemctl restart xray-dashboard
sudo systemctl stop xray-dashboard

# Xray
sudo systemctl status xray
sudo systemctl restart xray

# Логи в реальном времени
sudo journalctl -u xray-dashboard -u xray -f
```

---

## 🔄 Обновление

```bash
# Обновить Xray до последней версии
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
sudo systemctl restart xray

# Обновить Dashboard
cd /opt/xray-dashboard
git pull
sudo systemctl restart xray-dashboard
```

---

## ❌ Удаление

```bash
# Полное удаление Xray + Dashboard
sudo /opt/xray-dashboard/scripts/uninstall.sh

# Удалить только Dashboard (оставить Xray)
sudo systemctl stop xray-dashboard
sudo systemctl disable xray-dashboard
sudo rm -rf /opt/xray-dashboard
```

---

## 🤝 Поддержка протоколов в клиентах

| Протокол | v2rayN | v2rayNG | Happ | Nekoray | Clash.Meta |
|----------|--------|---------|------|---------|------------|
| VLESS WS | ✅ | ✅ | ✅ | ✅ | ✅ |
| VLESS XHTTP | ✅* | ✅* | ❌ | ✅ | ❌ |
| VLESS Reality | ✅ | ✅ | ✅ | ✅ | ❌ |
| VMess WS | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trojan XTLS | ✅ | ✅ | ✅ | ✅ | ✅ |

*Требуется xray-core backend

---

## 📝 TODO

- [ ] JWT авторизация для Dashboard
- [ ] WebSocket для live статистики
- [ ] Интеграция с Xray gRPC Stats API
- [ ] Docker Compose деплой
- [ ] Ansible playbook для multi-server
- [ ] Telegram bot для управления
- [ ] Traffic shaping (per-user limits)

---

## 📜 Лицензия

MIT License — см. [LICENSE](LICENSE)

---

## 🙏 Благодарности

- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — core VPN engine
- [FastAPI](https://fastapi.tiangolo.com/) — backend framework
- [Tailwind CSS](https://tailwindcss.com/) — UI styling

---

## ⚠️ Disclaimer

Этот проект предназначен для образовательных целей и повышения конфиденциальности в интернете. Пользователи несут ответственность за соблюдение местного законодательства и условий использования VPS-провайдера.