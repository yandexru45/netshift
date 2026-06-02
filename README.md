<div align="center">

# NetShift

[![Release](https://img.shields.io/github/v/release/yandexru45/podkop-evolution?style=flat-square)](https://github.com/yandexru45/podkop-evolution/releases)
[![License](https://img.shields.io/badge/license-GPL--2.0--or--later-blue?style=flat-square)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10%2B-orange?style=flat-square)](https://openwrt.org/)
[![Docs](https://img.shields.io/badge/docs-podkop.net-informational?style=flat-square)](https://podkop.net/)

</div>

---

<div align="center">

<img src="docs/screenshot.png" alt="NetShift в LuCI" width="800" />

</div>

---

**NetShift** - маршрутизатор трафика для OpenWrt. Направляйте нужные ресурсы в туннель, а остальное - напрямую. Открытое ПО на базе [sing-box](https://github.com/SagerNet/sing-box).

Это форк [itdoginfo/podkop](https://github.com/itdoginfo/podkop), значительно расширяющий функциональность.

> [!WARNING]
> Проект находится в стадии бета-версии. Возможны ошибки, нестабильная работа и существенные изменения функциональности.

---

## Функции

- [x] **Маршрутизация по доменам и подсетям** - нужное в туннель, остальное напрямую<br><sub>VLESS · Shadowsocks · Trojan · Hysteria2 · готовые community-списки</sub>
- [x] **Subscription URL** - ссылки подписки от провайдера с автообновлением и автовыбором лучшего сервера<br><sub>любая подписка remnawave · 3x-ui · marzban · github</sub>
- [x] **Переключаемое ядро sing-box** - стабильное ↔ sing-box-extended прямо из веб-интерфейса<br><sub>клиентский транспорт xhttp · установка и откат в один клик</sub>
- [x] **Веб-интерфейс LuCI** - дашборд, диагностика и настройки без ручной правки конфигов<br><sub>статус серверов · проверка соединения · логи</sub>
- [x] **Автоматическая миграция** - обновление со старого podkop переносит конфиг без перенастройки

## Вещи, которые необходимо знать перед установкой

<details open>
<summary><b>Системные требования</b></summary>

- OpenWrt **24.10** или выше.
- Минимум **25 МБ** свободного места. Устройства с флеш-памятью 16 МБ не поддерживаются.

</details>

<details>
<summary><b>Обновления и конфигурация</b></summary>

- При обновлении **обязательно** [очищайте кэш LuCI](https://podkop.net/docs/clear-browser-cache/).
- После обновления проверяйте конфигурацию - она может меняться между версиями.
- При старте NetShift модифицирует конфигурацию Dnsmasq.
- NetShift изменяет конфигурацию sing-box. Если используете собственную - заранее сохраните её.

</details>

<details>
<summary><b>Ограничения и особенности</b></summary>

- Если установлен **Getdomains**, его [необходимо удалить](https://github.com/itdoginfo/domain-routing-openwrt?tab=readme-ov-file#скрипт-для-удаления).
- **Dashboard** работает только по HTTP (особенность Clash API). По HTTPS или через домен может быть недоступен.

</details>

<details>
<summary><b>Поддержка и диагностика</b></summary>

- [Руководство по диагностике](https://podkop.net/docs/diagnostics/)
- Актуальные изменения - в [Telegram-чате](https://t.me/netshift_chat/2) (читайте закреплённые сообщения).
- При проблемах оставляйте технически грамотный фидбэк в GitHub Issues и Telegram-чате.

</details>

<details>
<summary><b>Миграция с podkop (0.8.0) и смена формата конфига (0.7.0)</b></summary>

**0.8.0 - переименование в NetShift.** Пакет теперь `netshift` (бинарь `/usr/bin/netshift`), конфиг - `/etc/config/netshift`, LuCI-приложение - `luci-app-netshift`. При обновлении старый конфиг `/etc/config/podkop` автоматически мигрируется в `/etc/config/netshift`, резервная копия сохраняется в `/etc/config/podkop.bak.pre-netshift`. туннель продолжит работать без перенастройки.

**0.7.0 - несовместимый формат конфига.** Старые значения несовместимы - нужно настроить заново. Скрипт установки обнаружит старую версию и предложит сделать это автоматически. Вручную:

```sh
mv /etc/config/netshift /etc/config/netshift-070
wget -O /etc/config/netshift https://raw.githubusercontent.com/yandexru45/podkop-evolution/refs/heads/main/netshift/files/etc/config/netshift
# затем настроить заново через LuCI или UCI
```

</details>

## Установка NetShift

Полная инструкция - в [документации](https://podkop.net/docs/install/).

Для установки и обновления достаточно одного скрипта:

```sh
sh <(wget -O - https://raw.githubusercontent.com/yandexru45/netshift/refs/heads/main/install.sh)
```

Интерфейс появится в LuCI: **Services → NetShift**.

<details>
<summary><b>Настройка подписки (Subscription URL) через UCI</b></summary>

При скачивании подписки отправляются заголовки:

| Заголовок | Значение |
|---|---|
| `User-Agent` | `singbox/<версия>` |
| `X-HWID` | уникальный идентификатор роутера |
| `X-Device-OS` | `OpenWrt Linux` |
| `X-Device-Model` | модель роутера |
| `X-Ver-OS` | версия ядра |

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

<details>
<summary><b>Ядро sing-box-extended (xhttp)</b></summary>

Переключение ядра между стабильным sing-box и сборкой **sing-box-extended** прямо из вкладки **Diagnostics** в LuCI:

- **Install extended** - установить расширенное ядро sing-box-extended.
- **Install stable** - вернуться на стабильное ядро.

После установки расширенного ядра становится доступен клиентский транспорт **xhttp** (только клиентский режим, не серверный). По умолчанию ставится стабильное ядро - extended включается по желанию.

</details>

## Project Structure

```
.
├── netshift/                       # Бэкенд-пакет (POSIX ash + jq)
│   ├── Makefile                    # Описание OpenWrt-пакета
│   └── files/
│       ├── etc/config/netshift     # UCI-конфиг по умолчанию
│       ├── etc/init.d/netshift     # procd init-скрипт
│       └── usr/
│           ├── bin/netshift        # Точка входа CLI (диспетчер команд)
│           └── lib/                # constants, helpers, nft, rulesets,
│                                   #   sing_box_config_*, updater, logging
│
├── luci-app-netshift/              # LuCI веб-интерфейс
│   ├── Makefile
│   ├── htdocs/.../view/netshift/   # main.js (автоген) + hand-written views
│   ├── po/                         # Переводы (генерируются из fe-app)
│   └── root/                       # menu.d · acl.d · uci-defaults
│
├── fe-app-netshift/                # TypeScript-исходник для main.js (tsup)
│   ├── src/netshift/               # fetchers · methods · services · tabs
│   ├── src/{validators,helpers,icons,partials}
│   └── locales/                    # Исходные переводы (netshift.pot / .po)
│
├── sdk/                            # Базовые образы OpenWrt SDK
├── Dockerfile-ipk · Dockerfile-apk # Сборка пакетов
└── install.sh                      # Установщик + миграция с podkop
```

## Build Artifacts

Пакеты собираются в Docker-образе OpenWrt SDK (24.10) и публикуются как релиз при push git-тега ([`.github/workflows/build.yml`](.github/workflows/build.yml)).

| Пакет | Формат | Назначение |
|---|---|---|
| `netshift` | `.ipk` / `.apk` | Бэкенд: CLI, init-скрипт, библиотеки, UCI-конфиг |
| `luci-app-netshift` | `.ipk` / `.apk` | Веб-интерфейс LuCI |
| `luci-i18n-netshift-ru` | `.ipk` / `.apk` | Русская локализация интерфейса |

Локальная сборка:

```sh
# ipk (большинство устройств OpenWrt 24.10)
docker build -f Dockerfile-ipk --build-arg NETSHIFT_VERSION=0.8.0 -t netshift:ipk .

# apk (новые сборки OpenWrt на apk)
docker build -f Dockerfile-apk --build-arg NETSHIFT_VERSION=0.8.0 -t netshift:apk .
```

> Требуется sing-box >= 1.12.0 и jq >= 1.7.1 на целевом устройстве.

## Star History

<a href="https://www.star-history.com/#yandexru45/podkop-evolution&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=yandexru45/podkop-evolution&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=yandexru45/podkop-evolution&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=yandexru45/podkop-evolution&type=Date" />
 </picture>
</a>

## Credits

- [itdoginfo/podkop](https://github.com/itdoginfo/podkop) - исходный проект, форком которого является NetShift.
- [sing-box](https://github.com/SagerNet/sing-box) - движок маршрутизации.

Лицензия: **GPL-2.0-or-later** - см. [LICENSE](LICENSE).

> [!IMPORTANT]
> Pull Request принимаются только после согласования с авторами в [Telegram-чате](https://t.me/netshift_chat/17).
