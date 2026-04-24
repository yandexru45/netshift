# Инструкция по тестированию фильтрации по странам

## Подготовка к тестированию

1. Соберите пакеты с изменениями:
```bash
# Для luci-app-podkop
cd luci-app-podkop
make

# Для podkop
cd ../podkop
make
```

2. Установите обновленные пакеты на роутер

## Тестирование через LuCI

1. Откройте веб-интерфейс LuCI
2. Перейдите в раздел **Services → Podkop → Section Configuration**
3. Выберите или создайте секцию с типом подключения **Proxy**
4. Выберите тип конфигурации **Subscription**
5. Заполните поле **Subscription URL** вашей ссылкой подписки
6. В поле **Заблокированные страны** введите коды стран, например: `RU CN`
7. Сохраните изменения
8. Перезапустите Podkop

## Тестирование через UCI

```bash
# Настройка через командную строку
uci set podkop.main.connection_type='proxy'
uci set podkop.main.proxy_config_type='subscription'
uci set podkop.main.subscription_url='https://your-provider.com/api/sub'
uci set podkop.main.subscription_blocked_countries='RU CN'
uci commit podkop

# Перезапуск сервиса
/etc/init.d/podkop restart
```

## Проверка результатов

### 1. Проверка логов

```bash
# Смотрим логи podkop
logread | grep -i "blocked\|skip.*country"

# Ожидаемый вывод:
# Skip server from blocked country: '🇷🇺 Moscow Server'
# Skipped 15 servers from blocked countries for section 'main'
```

### 2. Проверка конфигурации sing-box

```bash
# Показать конфигурацию sing-box
/usr/bin/podkop show_sing_box_config | jq '.outbounds[] | select(.type != "direct" and .type != "dns" and .type != "block") | .tag'

# Убедитесь, что серверы из заблокированных стран отсутствуют
```

### 3. Проверка через Dashboard

1. Откройте Dashboard (если включен YACD)
2. Проверьте список доступных серверов
3. Убедитесь, что серверы из заблокированных стран отсутствуют

## Тестовые сценарии

### Сценарий 1: Блокировка по ISO кодам
```bash
uci set podkop.main.subscription_blocked_countries='RU CN US'
```

### Сценарий 2: Блокировка по emoji флагам
```bash
uci set podkop.main.subscription_blocked_countries='🇷🇺 🇨🇳 🇺🇸'
```

### Сценарий 3: Смешанный формат
```bash
uci set podkop.main.subscription_blocked_countries='RU 🇨🇳 US'
```

### Сценарий 4: С группировкой по странам
```bash
uci set podkop.main.subscription_group_by_countries='1'
uci set podkop.main.subscription_blocked_countries='RU CN'
```

## Ожидаемое поведение

1. ✅ Серверы из заблокированных стран не появляются в конфигурации
2. ✅ В логах отображается количество пропущенных серверов
3. ✅ Остальные серверы работают нормально
4. ✅ Группировка по странам работает с оставшимися серверами
5. ✅ Автообновление подписки применяет фильтрацию при каждом обновлении

## Возможные проблемы

### Проблема: Все серверы отфильтрованы
**Симптом**: Ошибка "All subscription servers were filtered out"
**Решение**: Проверьте список заблокированных стран, возможно, вы заблокировали все доступные серверы

### Проблема: Фильтрация не работает
**Симптом**: Серверы из заблокированных стран все еще появляются
**Решение**: 
1. Проверьте формат названий серверов (должны начинаться с флага страны)
2. Убедитесь, что опция `subscription_blocked_countries` установлена корректно
3. Проверьте логи на наличие ошибок

### Проблема: Поле не отображается в LuCI
**Симптом**: Поле "Заблокированные страны" отсутствует в интерфейсе
**Решение**: 
1. Очистите кэш браузера (Ctrl+Shift+R)
2. Убедитесь, что выбран тип конфигурации "Subscription"
3. Проверьте, что установлена обновленная версия luci-app-podkop

## Отладка

```bash
# Включить debug логирование
uci set podkop.settings.log_level='debug'
uci commit podkop
/etc/init.d/podkop restart

# Смотреть логи в реальном времени
logread -f | grep podkop
```
