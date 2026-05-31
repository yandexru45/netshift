# Padkap Evolution

[![OpenWrt Smoke Tests](https://github.com/spgsroot/padkap-evolution/actions/workflows/openwrt-smoke-tests.yml/badge.svg)](https://github.com/spgsroot/padkap-evolution/actions/workflows/openwrt-smoke-tests.yml)
[![Build packages](https://github.com/spgsroot/padkap-evolution/actions/workflows/build.yml/badge.svg)](https://github.com/spgsroot/padkap-evolution/actions/workflows/build.yml)

> **Модифицированная сборка с расширенной функциональностью для OpenWrt**
>
> Маршрутизация трафика по доменам и подсетям на роутерах OpenWrt через sing-box.
> Добавлена поддержка подписок (HWID), глобального прокси, блокировки DoH, IPv6,
> фонового мониторинга с автовосстановлением и полной маршрутизации на уровне sing-box.

---

## Что нового в этом форке

| Фича | Описание |
|------|----------|
| **Подписки (Subscription)** | URL подписки от прокси-провайдера с HWID-авторизацией и автообновлением |
| **Полная маршрутизация через sing-box** | Весь LAN-трафик идёт через sing-box TProxy, все решения о маршрутизации — в sing-box rulesets |
| **Фоновый мониторинг** | После старта padkap следит за sing-box; при краше — восстанавливает DNS и перезапускает с экспоненциальной отсрочкой |
| **Блокировка DoH** | Тоггл для блокировки прямых подключений к публичным DoH-серверам (Cloudflare, Google, Quad9, AdGuard, OpenDNS, Yandex) |
| **Поддержка IPv6** | IPv6-правила nftables, TProxy, FakeIP, DNS (AAAA-записи), IPv6-валидаторы на фронтенде |
| **Global Proxy** | Режим «всё через прокси, кроме списка исключений» — обратная модель маршрутизации |
| **Docker-тестирование** | Контейнер OpenWrt rootfs для smoke-тестов перед загрузкой на роутер |

---

## Требования

- **OpenWrt 24.10** или новее (23.05 не поддерживается)
- **Минимум 25 МБ** свободного места на разделе overlay
- Установленный `sing-box` (>= 1.12.0)
- Отсутствие конфликтующих пакетов: `https-dns-proxy`, `nextdns`, `luci-app-passwall`

---

## Установка

Установщик всегда берёт последние `.ipk`/`.apk` пакеты из **GitHub Releases** этого форка:

```sh
sh <(wget -O - https://raw.githubusercontent.com/spgsroot/padkap-evolution/refs/heads/main/install.sh)
```

Скрипт установит:
- `padkap` — основной пакет
- `luci-app-padkap` — веб-интерфейс LuCI
- `luci-i18n-padkap-ru` — русская локализация (опционально)

После установки откройте LuCI → **Services → Padkap** и настройте секции.

> Если релиза ещё нет или GitHub API недоступен, установщик завершится с ошибкой и покажет ссылку на страницу релизов.

---

## Первый запуск

### Через LuCI (рекомендуется)

1. **Services → Padkap → Sections** — создайте секцию прокси
2. Выберите **Connection Type** = `Proxy`, **Configuration Type** = `Subscription` (или `Connection URL`)
3. Введите URL подписки или строку подключения
4. На вкладке **Settings** настройте DNS и сетевой интерфейс
5. Нажмите **Save & Apply**

### Через UCI (командная строка)

```sh
# Базовая настройка: прокси через подписку
uci set padkap.my_proxy=section
uci set padkap.my_proxy.connection_type='proxy'
uci set padkap.my_proxy.proxy_config_type='subscription'
uci set padkap.my_proxy.subscription_url='https://your-provider.com/api/sub'
uci set padkap.my_proxy.subscription_update_interval='1h'
uci add_list padkap.my_proxy.community_lists='russia_inside'
uci commit padkap

# Применить и запустить
/usr/bin/padkap start
```

---

## Настройка

### Подписки (Subscription)

При выборе `proxy_config_type = subscription` доступны опции:

| Опция | Значения | Описание |
|-------|----------|----------|
| `subscription_url` | URL | Ссылка подписки от провайдера |
| `subscription_update_interval` | `30m`, `1h`, `3h`, `6h`, `12h`, `1d` | Интервал автообновления |
| `subscription_group_by_countries` | `0`/`1` | Группировка серверов по флагам стран |

При скачивании подписки отправляются заголовки:
```
User-Agent: singbox/<версия>
X-HWID: xxxx-xxxx-xxxx-xxxx       # детерминированный ID роутера
X-Device-OS: OpenWrt Linux
X-Device-Model: <модель роутера>
X-Ver-OS: <версия ядра>
```

Ручное обновление подписки:
```sh
/usr/bin/padkap subscription_update
```

### Global Proxy — всё через прокси

Режим при котором **весь несовпадающий трафик** идёт через выбранный прокси,
а указанные списки (exclusion) — напрямую.

1. Создайте прокси-секцию (proxy/VPN) → включите **Global Proxy**
2. Создайте **exclusion**-секцию → добавьте списки доменов/подсетей для исключения

```
Все запросы → proxy-out (глобальный)
    .ru → direct-out (exclusion)
    локальные IP → direct-out (localv4/localv6)
```

Пример: «всё через прокси, кроме российских сайтов»
```sh
# Глобальный прокси
uci set padkap.global_out=section
uci set padkap.global_out.connection_type='proxy'
uci set padkap.global_out.proxy_config_type='subscription'
uci set padkap.global_out.subscription_url='https://example.com/sub'
uci set padkap.global_out.global_proxy='1'
uci commit padkap

# Исключение: .ru идёт напрямую
uci set padkap.ru_direct=section
uci set padkap.ru_direct.connection_type='exclusion'
uci add_list padkap.ru_direct.community_lists='russia_inside'
uci commit padkap
```

### Блокировка DoH-серверов

Предотвращает обход DNS-фильтрации роутера приложениями с собственным DoH.

**Settings → Block DoH Servers** — включите тоггл.

Блокируются прямые подключения к IP публичных DoH-серверов:
Cloudflare (`1.1.1.1`, `1.0.0.1`), Google (`8.8.8.8`, `8.8.4.4`),
Quad9 (`9.9.9.9`, `9.9.9.11`), OpenDNS, AdGuard, Yandex.

> ⚠️ Если ваш upstream DNS настроен на DoH (`dns_type = doh`), переключите его на
> UDP или DoT перед включением блокировки, иначе ваши собственные DNS-запросы
> тоже будут заблокированы.

### Мониторинг и автовосстановление

После успешного старта padkap форкает фоновый монитор, который:

1. Проверяет процесс sing-box каждые **10 секунд**
2. При краше — **немедленно восстанавливает DNS** (dnsmasq)
3. Пытается перезапустить sing-box с экспоненциальной отсрочкой:
   - 10с → 20с → 40с → 80с → 160с (максимум 300с)
4. После **5 последовательных крашей** — прекращает попытки, оставляет DNS восстановленным

Логи мониторинга:
```sh
logread | grep "monitor\|crash\|recovery"
```

### Ручное управление

```sh
/usr/bin/padkap start          # Запуск
/usr/bin/padkap stop           # Остановка
/usr/bin/padkap restart        # Перезапуск
/usr/bin/padkap reload         # Перезагрузка конфига
/usr/bin/padkap subscription_update  # Обновить подписку
/usr/bin/padkap global_check   # Полная диагностика
```

---

## Тестирование (Docker)

Smoke-тесты позволяют проверить работоспособность форка **до загрузки на роутер**:

```sh
# Сборка и полный прогон тестов
docker compose -f tests/docker-compose.yml up --build

# Отдельные тесты
docker compose -f tests/docker-compose.yml run --rm padkap-test deps
docker compose -f tests/docker-compose.yml run --rm padkap-test syntax
docker compose -f tests/docker-compose.yml run --rm padkap-test helpers
docker compose -f tests/docker-compose.yml run --rm padkap-test nft
docker compose -f tests/docker-compose.yml run --rm padkap-test subscription

# Без запуска сети (если нет интернета в контейнере)
TEST_SKIP_NETWORK=1 docker compose -f tests/docker-compose.yml up --build
```

Контейнер базируется на `openwrt/rootfs:x86-64`, устанавливает все зависимости
и прогоняет smoke-тесты: синтаксис shell-скриптов, валидацию конфигов,
генерацию sing-box JSON, jq-пайплайны, nftables, хелперы, парсинг подписок.

> **Ограничения контейнера**: TProxy и полный runtime sing-box требуют
> реального ядра с `kmod-nft-tproxy` — в Docker они недоступны.

### CI/CD

В форке настроены GitHub Actions:

| Workflow | Когда запускается | Что делает |
|----------|-------------------|------------|
| `OpenWrt Smoke Tests` | push/PR, изменения в `padkap/**`, `tests/**`, `install.sh`, workflows | Собирает OpenWrt rootfs Docker-контейнер и запускает `tests/entrypoint.sh all` |
| `Build packages` | push tag (`v*`/любой tag) | Сначала запускает smoke-тесты, затем собирает `.ipk` и `.apk`, публикует GitHub Release |
| `Frontend CI` | PR с изменениями `fe-app-padkap/**` | format/lint/test/build frontend |
| `Differential ShellCheck` | push/PR shell-файлов | ShellCheck по изменённым строкам |

Локальный тест перед релизом:

```sh
docker compose -f tests/docker-compose.yml up --build
```

Ожидаемый результат:

```text
Results: 42 passed / 0 failed
✓ ALL TESTS PASSED
```

### Создание релиза

Релиз создаётся тегом. Пример:

```sh
git tag v0.8.0
git push origin v0.8.0
```

После пуша тега workflow `Build packages`:
1. прогонит OpenWrt smoke-тесты;
2. соберёт пакеты `padkap`, `luci-app-padkap`, `luci-i18n-padkap-ru` для IPK/APK;
3. создаст GitHub Release с артефактами.

---

## Диагностика

```sh
# Статус sing-box
/usr/bin/padkap get_sing_box_status

# Статус padkap
/usr/bin/padkap get_status

# Показать конфиг sing-box
/usr/bin/padkap show_sing_box_config

# Полная проверка системы
/usr/bin/padkap global_check

# Проверка DNS
/usr/bin/padkap check_dns_available
```

Dashboard доступен через LuCI на вкладке **Dashboard** (только по HTTP,
из-за особенностей Clash API). Показывает графики трафика, список прокси-серверов,
задержки и ручное переключение между outbound'ами.

---

## Обновление с версии 0.7.0

Начиная с версии 0.7.0 изменена структура конфига. Установщик обнаружит старую
версию и предложит автоматическую миграцию.

При ручном обновлении:

```sh
# 1. Бэкап старого конфига
mv /etc/config/padkap /etc/config/padkap-070

# 2. Новый дефолтный конфиг
wget -O /etc/config/padkap \
  https://raw.githubusercontent.com/spgsroot/padkap-evolution/refs/heads/main/padkap/files/etc/config/padkap

# 3. Настроить заново через LuCI или UCI
```

---

## ToDo

- [ ] Unit тесты (BATS)
- [ ] Интеграционные тесты (OpenWrt rootfs + BATS)

---

## Обратная связь

- **Issues**: [github.com/spgsroot/padkap-evolution/issues](https://github.com/spgsroot/padkap-evolution/issues)
- **TG-чат**: [t.me/itdogchat](https://t.me/itdogchat/81758/420321)
