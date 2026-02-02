# xray-protocols-auto-deploy

Автоматическая установка и настройка Xray-core с генерацией конфигов под выбранные профили (VMess / Trojan / VLESS + транспорты XHTTP / mKCP / gRPC / WebSocket), включая REALITY и XTLS Vision Seed.

## Состав

- install.sh: установка, обновление и первичная настройка
- utils/: утилиты управления (клиенты, обновление, логи, автозапуск, geoip/geosite, BBR)
- generator/: генератор конфигов из профилей и шаблонов
- profiles/: описания профилей
- templates/: шаблоны блоков конфигурации
- tests/: smoke-проверки (включая xray -test)
- examples/: примеры сгенерированных конфигов

## Установка

Запуск в один шаг (рекомендуется):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Nerve11/xray-protocols-auto-deploy/test1/install.sh)
```

Важно: не используйте обратные кавычки вокруг URL (`` `...` ``), иначе bash будет пытаться выполнить URL как команду.

Если по какой-то причине вы хотите запускать установку строго из директории репозитория:

```bash
apt-get update -y && apt-get install -y git
git clone -b test1 https://github.com/Nerve11/xray-protocols-auto-deploy.git
cd xray-protocols-auto-deploy
bash install.sh
```

## TLS сертификаты

Для профилей с `security=tls` установщик автоматически создаёт самоподписанный сертификат и ключ и подставляет их в конфиг Xray.
Чтобы клиент мог подключиться к самоподписанному сертификату без ручной установки CA, в `client.json` автоматически включается `allowInsecure=true`.

Пути по умолчанию:

- Сертификат: `/usr/local/etc/xpad/certs/<domain>.crt`
- Ключ: `/usr/local/etc/xpad/certs/<domain>.key`

Если вы хотите использовать свой сертификат (например, Let’s Encrypt), задайте переменные окружения перед запуском:

```bash
export XPAD_TLS_CERT=/path/to/fullchain.pem
export XPAD_TLS_KEY=/path/to/privkey.pem
```
