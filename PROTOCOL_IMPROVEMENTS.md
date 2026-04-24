# Улучшения поддержки протоколов

## Обзор изменений

Улучшена поддержка протоколов Shadowsocks, Trojan, Hysteria и Hysteria2 с добавлением дополнительных параметров из URL.

## Shadowsocks

### Добавленные параметры

- **plugin** - плагин для обфускации (obfs-local, v2ray-plugin)
- **plugin-opts** - опции плагина

### Пример URL

```
ss://method:password@host:port?plugin=obfs-local&plugin-opts=obfs%3Dhttp%3Bobfs-host%3Dbing.com
```

### Поддерживаемые плагины

- `obfs-local` - Simple-obfs для обфускации трафика
- `v2ray-plugin` - V2Ray плагин с поддержкой WebSocket и TLS

## Trojan

### Добавленные параметры

- **network** - тип сети (tcp, udp, или оба)

### Пример URL

```
trojan://password@host:port?security=tls&sni=example.com&network=tcp&type=ws&path=/path
```

### Особенности

- Поддержка WebSocket и gRPC транспорта
- Поддержка TLS и Reality
- Настройка ALPN и fingerprint

## Hysteria2

### Добавленные параметры

- **network** - тип сети (tcp, udp)
- **salamander** - Salamander obfuscation (альтернатива obfs)

### Пример URL

```
hysteria2://password@host:port?obfs=salamander&obfs-password=secret&upmbps=100&downmbps=200&network=udp
```

или с использованием параметра salamander:

```
hy2://password@host:port?salamander=secret&upmbps=100&downmbps=200
```

### Особенности

- Автоматическое определение TLS
- Поддержка Salamander obfuscation
- Настройка пропускной способности (up/down mbps)

## Hysteria (v1) - НОВОЕ

### Поддерживаемые параметры

- **auth** - строка аутентификации (в userinfo части URL)
- **obfs** - пароль обфускации
- **protocol** - протокол: udp (по умолчанию), wechat-video, faketcp
- **upmbps** - пропускная способность загрузки в Mbps
- **downmbps** - пропускная способность скачивания в Mbps
- **network** - тип сети (tcp, udp)

### Пример URL

```
hysteria://auth_string@host:port?obfs=obfs_password&protocol=udp&upmbps=100&downmbps=200
```

### Особенности

- Поддержка различных протоколов (UDP, FakeTCP, WeChat Video)
- Обфускация трафика
- Настройка пропускной способности
- Автоматическая настройка TLS

## Технические детали

### Измененные файлы

1. **podkop/files/usr/lib/sing_box_config_facade.sh**
   - Добавлена обработка новых параметров для всех протоколов
   - Добавлена поддержка Hysteria v1

2. **podkop/files/usr/lib/sing_box_config_manager.sh**
   - Добавлена функция `sing_box_cm_add_hysteria_outbound()`
   - Обновлены существующие функции для поддержки новых параметров

### Обратная совместимость

Все изменения обратно совместимы. Существующие URL без новых параметров продолжат работать как раньше.

## Примеры использования

### Shadowsocks с obfs

```bash
uci set podkop.main.proxy_string='ss://aes-256-gcm:password@example.com:8388?plugin=obfs-local&plugin-opts=obfs%3Dhttp%3Bobfs-host%3Dbing.com'
```

### Trojan с WebSocket

```bash
uci set podkop.main.proxy_string='trojan://password@example.com:443?security=tls&sni=example.com&type=ws&path=/trojan&network=tcp'
```

### Hysteria2 с Salamander

```bash
uci set podkop.main.proxy_string='hy2://password@example.com:443?salamander=secret&upmbps=100&downmbps=200'
```

### Hysteria v1

```bash
uci set podkop.main.proxy_string='hysteria://auth_string@example.com:36712?obfs=obfs_password&protocol=udp&upmbps=50&downmbps=150'
```

## Проверка конфигурации

После настройки проверьте конфигурацию sing-box:

```bash
/usr/bin/podkop show_sing_box_config | jq '.outbounds[] | select(.type != "direct")'
```

## Совместимость

- Требуется sing-box >= 1.12.0
- Все параметры опциональны
- Неподдерживаемые параметры игнорируются

## Известные ограничения

1. **Shadowsocks**: sing-box не поддерживает top-level TLS для Shadowsocks (используйте плагины)
2. **Hysteria v1**: Устаревший протокол, рекомендуется использовать Hysteria2
3. **Plugin opts**: Сложные опции плагинов требуют URL-кодирования

## Отладка

Включите debug логирование для просмотра обработки параметров:

```bash
uci set podkop.settings.log_level='debug'
uci commit podkop
/etc/init.d/podkop restart
logread -f | grep podkop
```
