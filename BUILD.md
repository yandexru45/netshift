# Инструкция по локальной сборке Podkop Evolution

## Требования

- Docker
- Git
- Минимум 10GB свободного места на диске
- Linux/macOS (на Windows используйте WSL2)

## Быстрая сборка

### 1. Сборка IPK пакетов (для OpenWrt 24.10 с opkg)

```bash
# Клонируйте репозиторий (если еще не клонировали)
cd /home/xendr4x/podkop-evolution

# Соберите IPK пакеты
docker build -f Dockerfile-ipk -t podkop:local-ipk --build-arg PODKOP_VERSION="0.$(date +%d%m%Y)" .

# Создайте контейнер
docker create --name podkop-ipk podkop:local-ipk

# Скопируйте собранные пакеты
mkdir -p ./bin/ipk
docker cp podkop-ipk:/builder/bin/packages/x86_64/utilities/. ./bin/ipk/
docker cp podkop-ipk:/builder/bin/packages/x86_64/luci/. ./bin/ipk/

# Удалите контейнер
docker rm podkop-ipk

# Пакеты находятся в ./bin/ipk/
ls -lh ./bin/ipk/*.ipk
```

### 2. Сборка APK пакетов (для OpenWrt 24.10+ с apk)

**ВАЖНО:** APK требует версию в формате X.Y.Z (например, 0.8.0), а не 0.DDMMYYYY

```bash
cd /home/xendr4x/podkop-evolution

# Соберите APK пакеты с правильной версией
docker build -f Dockerfile-apk -t podkop:local-apk --build-arg PODKOP_VERSION="0.8.0" .

# Создайте контейнер
docker create --name podkop-apk podkop:local-apk

# Скопируйте собранные пакеты
mkdir -p ./bin/apk
docker cp podkop-apk:/builder/bin/packages/x86_64/utilities/. ./bin/apk/
docker cp podkop-apk:/builder/bin/packages/x86_64/luci/. ./bin/apk/

# Удалите контейнер
docker rm podkop-apk

# Пакеты находятся в ./bin/apk/
ls -lh ./bin/apk/*.apk
```

## Скрипт для автоматической сборки

Создайте файл `build.sh`:

```bash
#!/bin/bash

set -e

PACKAGE_TYPE="${1:-ipk}"  # ipk или apk
VERSION="${2}"

# Автоматическое определение версии
if [ -z "$VERSION" ]; then
    if [ "$PACKAGE_TYPE" = "apk" ]; then
        # APK требует формат X.Y.Z
        VERSION="0.8.0"
        echo "Using default APK version: $VERSION"
    else
        # IPK может использовать любой формат
        VERSION="0.$(date +%d%m%Y)"
        echo "Using date-based IPK version: $VERSION"
    fi
fi

echo "Building $PACKAGE_TYPE packages, version: $VERSION"

# Сборка
docker build -f Dockerfile-$PACKAGE_TYPE \
    -t podkop:local-$PACKAGE_TYPE \
    --build-arg PODKOP_VERSION="$VERSION" \
    .

# Создание контейнера
docker create --name podkop-$PACKAGE_TYPE podkop:local-$PACKAGE_TYPE

# Копирование пакетов
mkdir -p ./bin/$PACKAGE_TYPE
docker cp podkop-$PACKAGE_TYPE:/builder/bin/packages/x86_64/utilities/. ./bin/$PACKAGE_TYPE/
docker cp podkop-$PACKAGE_TYPE:/builder/bin/packages/x86_64/luci/. ./bin/$PACKAGE_TYPE/

# Очистка
docker rm podkop-$PACKAGE_TYPE

echo "Build complete! Packages are in ./bin/$PACKAGE_TYPE/"
ls -lh ./bin/$PACKAGE_TYPE/*.$PACKAGE_TYPE
```

Использование:

```bash
chmod +x build.sh

# Собрать IPK (автоматическая версия 0.DDMMYYYY)
./build.sh ipk

# Собрать APK (автоматическая версия 0.8.0)
./build.sh apk

# Собрать с кастомной версией
./build.sh ipk 0.8.0
./build.sh apk 0.8.1
```

## Установка на роутер

### Через SCP

```bash
# Скопируйте пакеты на роутер
scp ./bin/ipk/podkop*.ipk root@192.168.1.1:/tmp/
scp ./bin/ipk/luci-app-podkop*.ipk root@192.168.1.1:/tmp/
scp ./bin/ipk/luci-i18n-podkop-ru*.ipk root@192.168.1.1:/tmp/  # опционально

# Подключитесь к роутеру
ssh root@192.168.1.1

# Установите пакеты
cd /tmp
opkg install podkop*.ipk
opkg install luci-app-podkop*.ipk
opkg install luci-i18n-podkop-ru*.ipk  # опционально

# Перезапустите сервис
/etc/init.d/podkop restart
```

### Через веб-интерфейс

1. Откройте LuCI: `http://192.168.1.1`
2. Перейдите в **System → Software**
3. Нажмите **Upload Package...**
4. Загрузите файлы по очереди:
   - `podkop-*.ipk`
   - `luci-app-podkop-*.ipk`
   - `luci-i18n-podkop-ru-*.ipk` (опционально)
5. Очистите кэш браузера (Ctrl+Shift+R)

## Сборка только frontend

Если вы изменили только frontend (TypeScript):

```bash
cd fe-app-podkop

# Установите зависимости (первый раз)
yarn install

# Соберите
yarn build

# Скопируйте результат в luci-app-podkop
cp dist/main.js ../luci-app-podkop/htdocs/luci-static/resources/view/podkop/main.js
```

## Отладка сборки

### Просмотр логов сборки

```bash
# Сборка с подробными логами
docker build -f Dockerfile-ipk -t podkop:debug --build-arg PODKOP_VERSION="debug" . 2>&1 | tee build.log
```

### Вход в контейнер для отладки

```bash
# Запустите контейнер в интерактивном режиме
docker run -it --rm \
    -v $(pwd)/podkop:/builder/package/feeds/utilities/podkop \
    -v $(pwd)/luci-app-podkop:/builder/package/feeds/luci/luci-app-podkop \
    itdoginfo/openwrt-sdk-ipk:24.10.3 \
    /bin/bash

# Внутри контейнера
cd /builder
make defconfig
make package/podkop/compile V=s
```

### Проверка собранных пакетов

```bash
# Просмотр содержимого IPK
tar -tzf ./bin/ipk/podkop*.ipk

# Извлечение и просмотр
mkdir -p /tmp/podkop-check
cd /tmp/podkop-check
tar -xzf /path/to/podkop*.ipk
tar -xzf data.tar.gz
ls -la
```

## Очистка

```bash
# Удалить собранные пакеты
rm -rf ./bin/

# Удалить Docker образы
docker rmi podkop:local-ipk podkop:local-apk

# Удалить все неиспользуемые Docker образы
docker system prune -a
```

## Частые проблемы

### Ошибка: "No space left on device"

```bash
# Очистите Docker
docker system prune -a --volumes
```

### Ошибка сборки: "Package not found"

```bash
# Убедитесь, что используете правильный SDK образ
docker pull itdoginfo/openwrt-sdk-ipk:24.10.3
docker pull itdoginfo/openwrt-sdk-apk:09102025
```

### Пакеты не устанавливаются на роутере

```bash
# Проверьте архитектуру
opkg print-architecture

# Убедитесь, что версия OpenWrt совместима
cat /etc/openwrt_release
```

## Сборка для разных архитектур

По умолчанию собирается для x86_64. Для других архитектур нужно использовать соответствующий SDK:

```bash
# Для ARM (например, Raspberry Pi)
# Используйте другой SDK образ или соберите свой
```

## CI/CD

Проект использует GitHub Actions для автоматической сборки при создании тега:

```bash
# Создайте тег
git tag v0.8.0
git push origin v0.8.0

# GitHub Actions автоматически соберет и создаст release
```

## Дополнительная информация

- OpenWrt SDK документация: https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk
- Docker Hub образы: https://hub.docker.com/u/itdoginfo
- Документация проекта: https://podkop.net/
