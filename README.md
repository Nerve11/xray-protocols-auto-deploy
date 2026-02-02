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

