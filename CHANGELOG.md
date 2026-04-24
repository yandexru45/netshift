# Сводка изменений Podkop Evolution

## Дата: 2026-04-24

### 1. Фильтрация серверов подписки по странам

#### Описание
Добавлена возможность блокировать серверы из определенных стран при использовании subscription URL.

#### Изменения
- Добавлена UCI опция `subscription_blocked_countries`
- Добавлено поле в LuCI интерфейсе
- Реализована фильтрация на уровне `sing_box_cf_add_subscription_outbounds()`
- Поддержка ISO кодов (RU, CN) и emoji флагов (🇷🇺, 🇨🇳)

#### Использование
```bash
uci set podkop.main.subscription_blocked_countries='RU CN'
uci commit podkop
/etc/init.d/podkop restart
```

#### Файлы
- `podkop/files/usr/bin/podkop` - чтение опции из UCI
- `podkop/files/usr/lib/sing_box_config_facade.sh` - логика фильтрации
- `podkop/files/etc/config/podkop` - пример конфигурации
- `luci-app-podkop/htdocs/luci-static/resources/view/podkop/section.js` - UI поле
- `fe-app-podkop/src/podkop/types.ts` - TypeScript типы

#### Документация
- `COUNTRY_FILTERING.md` - полное описание функциональности
- `TESTING_COUNTRY_FILTER.md` - инструкция по тестированию

---

### 2. Улучшение поддержки протоколов

#### Shadowsocks
**Добавленные параметры:**
- `plugin` - плагин обфускации (obfs-local, v2ray-plugin)
- `plugin-opts` - опции плагина

**Пример:**
```
ss://method:password@host:port?plugin=obfs-local&plugin-opts=obfs%3Dhttp
```

#### Trojan
**Добавленные параметры:**
- `network` - тип сети (tcp, udp)

**Пример:**
```
trojan://password@host:port?security=tls&network=tcp&type=ws
```

#### Hysteria2
**Добавленные параметры:**
- `network` - тип сети (tcp, udp)
- `salamander` - Salamander obfuscation

**Пример:**
```
hy2://password@host:port?salamander=secret&upmbps=100&downmbps=200
```

#### Hysteria v1 (НОВОЕ)
**Полная поддержка протокола:**
- `auth` - строка аутентификации
- `obfs` - обфускация
- `protocol` - udp/wechat-video/faketcp
- `upmbps/downmbps` - пропускная способность

**Пример:**
```
hysteria://auth@host:port?obfs=secret&protocol=udp&upmbps=50&downmbps=150
```

#### Файлы
- `podkop/files/usr/lib/sing_box_config_facade.sh` - обработка параметров
- `podkop/files/usr/lib/sing_box_config_manager.sh` - функция для Hysteria v1

#### Документация
- `PROTOCOL_IMPROVEMENTS.md` - полное описание улучшений

---

## Статистика изменений

```
6 файлов изменено
176 строк добавлено
8 строк удалено
```

### Измененные файлы:
1. `fe-app-podkop/src/podkop/types.ts` (+1)
2. `luci-app-podkop/htdocs/luci-static/resources/view/podkop/section.js` (+10)
3. `podkop/files/etc/config/podkop` (+1)
4. `podkop/files/usr/bin/podkop` (+5, -2)
5. `podkop/files/usr/lib/sing_box_config_facade.sh` (+102, -6)
6. `podkop/files/usr/lib/sing_box_config_manager.sh` (+57)

### Созданные документы:
1. `COUNTRY_FILTERING.md` - описание фильтрации по странам
2. `TESTING_COUNTRY_FILTER.md` - инструкция по тестированию
3. `PROTOCOL_IMPROVEMENTS.md` - описание улучшений протоколов
4. `CHANGELOG.md` - этот файл

---

## Требования

- OpenWrt 24.10+
- sing-box >= 1.12.0
- jq >= 1.7.1
- coreutils-base64 >= 9.7

---

## Обратная совместимость

Все изменения полностью обратно совместимы:
- Существующие конфигурации продолжат работать
- Новые параметры опциональны
- Отсутствие новых параметров не влияет на работу

---

## Тестирование

### Фильтрация по странам
```bash
# Настройка
uci set podkop.main.subscription_blocked_countries='RU CN'
uci commit podkop
/etc/init.d/podkop restart

# Проверка логов
logread | grep -i "blocked\|skip.*country"
```

### Протоколы
```bash
# Проверка конфигурации
/usr/bin/podkop show_sing_box_config | jq '.outbounds[] | select(.type != "direct")'

# Проверка валидности
sing-box -c /etc/sing-box/config.json check
```

---

## Следующие шаги

1. Собрать пакеты с изменениями
2. Протестировать на тестовом роутере
3. Проверить работу фильтрации по странам
4. Проверить работу новых параметров протоколов
5. Обновить документацию на сайте (если есть)
6. Создать PR в основной репозиторий

---

## Известные ограничения

1. Фильтрация по странам работает только если названия серверов начинаются с флага страны
2. Shadowsocks не поддерживает top-level TLS (используйте плагины)
3. Hysteria v1 - устаревший протокол, рекомендуется Hysteria2
4. Сложные опции плагинов требуют URL-кодирования

---

## Контакты и поддержка

- GitHub: https://github.com/yandexru45/podkop-evolution
- Telegram: https://t.me/itdogchat
- Документация: https://podkop.net/
