<div align="center">

```
   ╔╗╔╔═╗╔╦╗╔═╗╦ ╦╦╔═╗╔╦╗
   ║║║║╣  ║ ╚═╗╠═╣║╠╣  ║
   ╝╚╝╚═╝ ╩ ╚═╝╩ ╩╩╚   ╩
        shift your traffic
```

# NetShift

**Маршрутизация трафика для OpenWrt — нужное в туннель, остальное напрямую.**

Открытое ПО на базе [sing-box](https://github.com/SagerNet/sing-box) · форк [itdoginfo/podkop](https://github.com/itdoginfo/podkop) с поддержкой Subscription URL, HWID и переключаемого ядра sing-box-extended.

[![Release](https://img.shields.io/github/v/release/yandexru45/podkop-evolution?style=flat-square)](https://github.com/yandexru45/podkop-evolution/releases)
[![License](https://img.shields.io/badge/license-GPL--2.0--or--later-blue?style=flat-square)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10%2B-orange?style=flat-square)](https://openwrt.org/)
[![Docs](https://img.shields.io/badge/docs-podkop.net-informational?style=flat-square)](https://podkop.net/)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/itdoginfo/podkop)

</div>

> [!WARNING]
> Проект находится в стадии бета-версии. Возможны ошибки, нестабильная работа и существенные изменения функциональности.

---

## Возможности

- [x] **Маршрутизация по доменам и подсетям** — направляйте нужные ресурсы в туннель, остальное идёт напрямую<br>　<sub>VLESS · Shadowsocks · Trojan · Hysteria2 · готовые community-списки</sub>
- [x] **Subscription URL** — ссылки подписки от провайдера с автообновлением и автовыбором лучшего сервера<br>　<sub>кастомные заголовки HWID / Device-OS / Device-Model · URLTest · ручное переключение</sub>
- [x] **Переключаемое ядро sing-box** — стабильное ↔ sing-box-extended прямо из веб-интерфейса<br>　<sub>клиентский транспорт xhttp · установка/откат в один клик</sub>
- [x] **Веб-интерфейс LuCI** — дашборд, диагностика и настройки без правки конфигов<br>　<sub>статус серверов · проверка соединения · логи</sub>
- [x] **Автоматическая миграция** — обновление со старого podkop переносит конфиг без перенастройки

## Скриншоты

> Интерфейс доступен в LuCI: **Services → NetShift**.
> _(скриншоты будут добавлены)_

## Установка

Полная инструкция — в [документации](https://podkop.net/docs/install/).

Для установки и обновления достаточно одного скрипта:

```sh
sh <(wget -O - https://raw.githubusercontent.com/yandexru45/podkop-evolution/refs/heads/main/install.sh)
```

> [!IMPORTANT]
> Перед установкой ознакомьтесь с разделом [**Перед установкой**](#перед-установкой) ниже — там системные требования и важные ограничения.

## Перед установкой

<details open>
<summary><b>Системные требования</b></summary>

- OpenWrt **24.10** или выше.
- Минимум **25 МБ** свободного места. Устройства с флеш-памятью 16 МБ не поддерживаются.

</details>

<details>
<summary><b>Обновления и конфигурация</b></summary>

- При обновлении **обязательно** [очищайте кэш LuCI](https://podkop.net/docs/clear-browser-cache/).
- После обновления проверяйте конфигурацию — она может меняться между версиями.
- При старте NetShift модифицирует конфигурацию Dnsmasq.
- NetShift изменяет конфигурацию sing-box. Если используете собственную — заранее сохраните её.

</details>

<details>
<summary><b>Ограничения и особенности</b></summary>

- Если установлен **Getdomains**, его [необходимо удалить](https://github.com/itdoginfo/domain-routing-openwrt?tab=readme-ov-file#скрипт-для-удаления).
- **Dashboard** работает только по HTTP (особенность Clash API). По HTTPS или через домен может быть недоступен.

</details>

<details>
<summary><b>Поддержка и диагностика</b></summary>

- [Руководство по диагностике](https://podkop.net/docs/diagnostics/)
- Актуальные изменения — в [Telegram-чате](https://t.me/itdogchat/81758/420321) (читайте закреплённые сообщения).
- При проблемах оставляйте технически грамотный фидбэк в GitHub Issues и Telegram-чате.

</details>

## Subscription URL

Поддержка ссылок подписки от провайдера прокси. При выборе типа конфигурации **Subscription** в LuCI:

- Введите URL подписки от вашего провайдера.
- Выберите интервал автообновления (от 30 минут до 1 дня).
- Все серверы из подписки автоматически появятся в дашборде.
- Автовыбор лучшего сервера по задержке (URLTest) и ручное переключение.

При скачивании подписки отправляются заголовки:

| Заголовок | Значение |
|---|---|
| `User-Agent` | `singbox/<версия>` |
| `X-HWID` | уникальный идентификатор роутера |
| `X-Device-OS` | `OpenWrt Linux` |
| `X-Device-Model` | модель роутера |
| `X-Ver-OS` | версия ядра |

<details>
<summary><b>Пример настройки через UCI</b></summary>

```sh
uci set netshift.my_sub=section
uci set netshift.my_sub.connection_type='proxy'
uci set netshift.my_sub.proxy_config_type='subscription'
uci set netshift.my_sub.subscription_url='https://your-provider.com/api/sub'
uci set netshift.my_sub.subscription_update_interval='1h'
uci add_list netshift.my_sub.community_lists='russia_inside'
uci commit netshift
```

Ручное обновление подписки:

```sh
/usr/bin/netshift subscription_update
```

</details>

## Ядро sing-box-extended (xhttp)

Переключение ядра между стабильным sing-box и сборкой **sing-box-extended** прямо из вкладки **Diagnostics** в LuCI:

- **Install extended** — установить расширенное ядро sing-box-extended.
- **Install stable** — вернуться на стабильное ядро.

После установки расширенного ядра становится доступен клиентский транспорт **xhttp**. Поддерживается только клиентский режим (не серверный). По умолчанию ставится стабильное ядро — extended включается по желанию.

## Миграция

<details>
<summary><b>0.8.0 — переименование в NetShift</b></summary>

С версии 0.8.0 проект переименован из `podkop` в **NetShift**:

- пакет — `netshift` (бинарь `/usr/bin/netshift`);
- конфигурация — `/etc/config/netshift`;
- LuCI-приложение — `luci-app-netshift`.

При обновлении старый конфиг `/etc/config/podkop` **автоматически мигрируется** в `/etc/config/netshift`, резервная копия сохраняется в `/etc/config/podkop.bak.pre-netshift`. VPN продолжит работать без перенастройки.

</details>

<details>
<summary><b>0.7.0 — несовместимый формат конфига</b></summary>

С версии 0.7.0 изменена структура конфига (на тот момент — `/etc/config/podkop`). Старые значения несовместимы — нужно настроить заново. Скрипт установки обнаружит старую версию и предложит сделать это автоматически.

Вручную:

```sh
# 1. Забэкапить старый конфиг
mv /etc/config/netshift /etc/config/netshift-070
# 2. Стянуть новый дефолтный конфиг
wget -O /etc/config/netshift https://raw.githubusercontent.com/yandexru45/podkop-evolution/refs/heads/main/netshift/files/etc/config/netshift
# 3. Настроить заново через LuCI или UCI
```

</details>

## Документация

Полная документация: **<https://podkop.net/>**

## Дорожная карта

> [!IMPORTANT]
> Pull Request принимаются только после согласования с авторами в [Telegram-чате](https://t.me/itdogchat/81758/420321). PR без предварительного обсуждения не рассматриваются.

- [x] [Подписка (Subscription URL)](https://github.com/itdoginfo/podkop/issues/118) — **реализовано**
- [x] Переключаемое ядро sing-box-extended + xhttp — **реализовано**
- [ ] Весь трафик в sing-box и маршрутизация полностью на его уровне.
- [ ] Фоновый режим со слежением за состоянием sing-box и авто-restore dnsmasq при падении. [Issue](https://github.com/itdoginfo/podkop/issues/111)
- [ ] Опция, ограничивающая доступ к DoH-серверам.
- [ ] IPv6 (после наполнения Wiki).

**Тесты:**

- [ ] Unit-тесты (BATS)
- [ ] Интеграционные тесты бэкенда (OpenWrt rootfs + BATS)

## Благодарности

- [itdoginfo/podkop](https://github.com/itdoginfo/podkop) — исходный проект, форком которого является NetShift.
- [sing-box](https://github.com/SagerNet/sing-box) — движок маршрутизации.

## Лицензия

GPL-2.0-or-later — см. [LICENSE](LICENSE).

> [!WARNING]
> Программное обеспечение предоставляется «как есть», без каких-либо явных или подразумеваемых гарантий, включая гарантии коммерческой пригодности и соответствия определённой цели. Правообладатели и участники проекта не несут ответственности за любые убытки, возникшие в результате использования ПО.
