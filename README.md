# NetShift

> **Форк с поддержкой Subscription URL + HWID и переключаемым ядром sing-box-extended (xhttp)**
>
> NetShift добавляет поддержку ссылок подписки (subscription URL) с кастомными заголовками (HWID, Device-OS, Device-Model) и автоматическим обновлением, а также переключение ядра на sing-box-extended с поддержкой клиентского транспорта xhttp. Основан на [itdoginfo/podkop](https://github.com/itdoginfo/podkop).

Маршрутизация трафика для OpenWrt.

Направляйте нужные ресурсы в туннель, а остальное — напрямую. Открытое программное обеспечение на базе [sing-box](https://github.com/SagerNet/sing-box).

> [!WARNING]
> Проект находится в стадии бета-версии. Возможны ошибки, нестабильная работа и существенные изменения функциональности.

---

# Вещи, которые вам нужно знать перед установкой

### Обновления и конфигурация
- При обновлении **обязательно** [очищайте кэш LuCI](https://podkop.net/docs/clear-browser-cache/).
- После обновления проверяйте конфигурацию — она может изменяться между версиями.
- При старте NetShift модифицируется конфигурация Dnsmasq.
- NetShift изменяет конфигурацию sing-box. Если вы используете собственную конфигурацию, заранее сохраните её.

### Системные требования
- Требуется OpenWrt 24.10 или выше.
- Необходимо минимум 25 МБ свободного места на устройстве. Устройства с флеш-памятью 16 МБ не поддерживаются.

### Важные ограничения и особенности
- Если установлен Getdomains, его [необходимо удалить](https://github.com/itdoginfo/domain-routing-openwrt?tab=readme-ov-file#скрипт-для-удаления)
- Dashboard доступен только при подключении по HTTP (из-за особенностей Clash API). При использовании HTTPS или домена работа может быть недоступна.

### Поддержка и диагностика
- [Руководство по диагностике](https://podkop.net/docs/diagnostics/)
- Актуальные изменения публикуются в [Telegram-чате](https://t.me/itdogchat/81758/420321). Пожалуйста, ознакомьтесь с закрепленными сообщениями.
- При возникновении проблем оставляйте технически грамотный фидбэк в GitHub Issues и Telegram-чате.


# Документация
https://podkop.net/

# Установка NetShift
Полная информация в [документации](https://podkop.net/docs/install/)

Для установки и обновления достаточно выполнить один скрипт:
```
sh <(wget -O - https://raw.githubusercontent.com/yandexru45/podkop-evolution/refs/heads/main/install.sh)
```

## Новое в NetShift: Подписки (Subscription)

Добавлена поддержка subscription URL — ссылки подписки от провайдера прокси. При выборе типа конфигурации **Subscription** в LuCI:

- Введите URL подписки от вашего провайдера
- Выберите интервал автообновления (от 30 минут до 1 дня)
- Все серверы из подписки автоматически появятся в дашборде
- Автоматический выбор лучшего сервера по задержке (URLTest)
- Ручное переключение между серверами через дашборд

При скачивании подписки отправляются заголовки:
- `User-Agent: singbox/<версия>`
- `X-HWID` — уникальный идентификатор роутера
- `X-Device-OS: OpenWrt Linux`
- `X-Device-Model` — модель роутера
- `X-Ver-OS` — версия ядра

Пример конфигурации через UCI:
```
uci set netshift.my_sub=section
uci set netshift.my_sub.connection_type='proxy'
uci set netshift.my_sub.proxy_config_type='subscription'
uci set netshift.my_sub.subscription_url='https://your-provider.com/api/sub'
uci set netshift.my_sub.subscription_update_interval='1h'
uci add_list netshift.my_sub.community_lists='russia_inside'
uci commit netshift
```

Ручное обновление подписки:
```
/usr/bin/netshift subscription_update
```

## Новое в NetShift: ядро sing-box-extended (xhttp)

NetShift позволяет переключать ядро между стабильным sing-box и сборкой
sing-box-extended прямо из вкладки **Diagnostics** в LuCI:

- **Install extended** — установить расширенное ядро sing-box-extended.
- **Install stable** — вернуться на стабильное ядро sing-box.

После установки расширенного ядра становится доступен клиентский транспорт
**xhttp**. Поддерживается только клиентский режим xhttp (не серверный).

## Изменения 0.8.0 — переименование в NetShift
Начиная с версии 0.8.0 проект переименован из `podkop` в **NetShift**. Пакет
теперь называется `netshift` (бинарь `/usr/bin/netshift`), а конфигурация
переехала на `/etc/config/netshift`. LuCI-приложение — `luci-app-netshift`.

При обновлении старый конфиг `/etc/config/podkop` автоматически мигрируется в
`/etc/config/netshift`, а резервная копия сохраняется в
`/etc/config/podkop.bak.pre-netshift`.

## Изменения 0.7.0
Начиная с версии 0.7.0 изменена структура конфига `/etc/config/netshift`
(на тот момент — `/etc/config/podkop`). Старые значения несовместимы с новыми.
Нужно заново настроить NetShift.

Скрипт установки обнаружит старую версию и предупредит вас об этом. Если вы согласитесь, то он сделает автоматически написанное ниже.

При обновлении вручную нужно:

0. Не ныть в issue и чатик.
1. Забэкапить старый конфиг:
```
mv /etc/config/netshift /etc/config/netshift-070
```
2. Стянуть новый дефолтный конфиг:
```
wget -O /etc/config/netshift https://raw.githubusercontent.com/yandexru45/podkop-evolution/refs/heads/main/netshift/files/etc/config/netshift
```
3. Настроить заново ваш NetShift через Luci или UCI.

# ToDo

> [!IMPORTANT]  
> Pull Request принимаются только после согласования с авторами в Telegram-чате. На данный момент PR без предварительного обсуждения не рассматриваются.

## Будущее
- [x] [Подписка](https://github.com/itdoginfo/podkop/issues/118) — **реализовано в NetShift!**
- [ ] Весь трафик в sing-box и маршрутизация полностью на его уровне.
- [ ] При успешном запуске переходит в фоновый режим и следит за состоянием sing-box. Если вдруг идёт exit 1, выполняется dnsmasq restore и снова следит за состоянием. [Issue](https://github.com/itdoginfo/podkop/issues/111)
- [ ] Галочка, которая режет доступ к doh серверам.
- [ ] IPv6. Только после наполнения Wiki.

## Тесты
- [ ] Unit тесты (BATS)
- [ ] Интеграционные тесты бекенда (OpenWrt rootfs + BATS)

> [!WARNING]
> Данное программное обеспечение предоставляется «как есть», без каких-либо явных или подразумеваемых гарантий, включая гарантии коммерческой пригодности и соответствия определённой цели. 
> 
> Правообладатели и участники проекта не несут ответственности за любые прямые, косвенные, случайные, специальные или иные убытки, возникшие в результате использования программного обеспечения, включая потерю данных, прибыли или прерывание деятельности, даже если они были предупреждены о возможности таких последствий.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/itdoginfo/podkop)
