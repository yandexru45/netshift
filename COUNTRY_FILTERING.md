# Фильтрация серверов подписки по странам

## Описание

Добавлена возможность блокировать серверы из определенных стран при использовании subscription URL. Серверы из заблокированных стран не будут добавлены в конфигурацию sing-box.

## Использование

### Через UCI

```bash
uci set podkop.my_section.subscription_blocked_countries='RU CN'
uci commit podkop
/etc/init.d/podkop restart
```

### Через LuCI

1. Откройте раздел конфигурации подписки
2. Найдите поле "Заблокированные страны"
3. Введите список стран через пробел или запятую

### Поддерживаемые форматы

- **ISO коды**: `RU CN US` (двухбуквенные коды стран)
- **Emoji флаги**: `🇷🇺 🇨🇳 🇺🇸` (флаги стран в формате emoji)
- **Смешанный формат**: `RU 🇨🇳 US` (можно комбинировать)

## Как это работает

1. При загрузке подписки функция `sing_box_cf_add_subscription_outbounds` проверяет название каждого сервера
2. Извлекается флаг страны из начала названия сервера (например, "🇷🇺 Moscow" → 🇷🇺)
3. Флаг конвертируется в ISO код (🇷🇺 → RU)
4. Если страна в списке заблокированных, сервер пропускается и не добавляется в конфигурацию
5. В логах отображается количество пропущенных серверов

## Примеры

### Блокировка серверов из России и Китая

```bash
uci set podkop.main.subscription_blocked_countries='RU CN'
```

### Блокировка с использованием emoji

```bash
uci set podkop.main.subscription_blocked_countries='🇷🇺 🇨🇳'
```

### Блокировка нескольких стран

```bash
uci set podkop.main.subscription_blocked_countries='RU CN US DE FR'
```

## Логирование

При применении фильтрации в логах появятся сообщения:

```
Skip server from blocked country: '🇷🇺 Moscow Server'
Skipped 15 servers from blocked countries for section 'main'
Added 42 subscription outbounds for section 'main'
```

## Совместимость

- Работает с группировкой по странам (`subscription_group_by_countries`)
- Совместимо с автообновлением подписок
- Не влияет на уже добавленные серверы из других типов конфигурации

## Технические детали

### Измененные файлы

1. `podkop/files/usr/lib/sing_box_config_facade.sh` - добавлена логика фильтрации в функцию `sing_box_cf_add_subscription_outbounds`
2. `podkop/files/usr/bin/podkop` - добавлено чтение опции `subscription_blocked_countries` из UCI
3. `podkop/files/etc/config/podkop` - добавлен пример использования опции в конфиге
4. `luci-app-podkop/htdocs/luci-static/resources/view/podkop/section.js` - добавлено поле в UI
5. `fe-app-podkop/src/podkop/types.ts` - добавлен тип для новой опции

### Алгоритм определения страны

Функция извлекает флаг страны из названия сервера, используя Unicode Regional Indicator Symbols (U+1F1E6 - U+1F1FF). Если первые два символа названия сервера являются региональными индикаторами, они интерпретируются как флаг страны и конвертируются в ISO код.

Пример: 🇷🇺 (U+1F1F7 U+1F1FA) → RU (R=1F1F7-1F1E6+65=82='R', U=1F1FA-1F1E6+65=85='U')
