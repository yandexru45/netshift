# Инструкция по локальной сборке - ОБНОВЛЕНО

## Проблема с APK SDK

**ВАЖНО:** Текущий Dockerfile-apk не сохраняет собранные пакеты в финальном образе. Пакеты создаются во время сборки, но теряются после завершения.

## Рекомендация: используйте IPK

Для локальной сборки рекомендуется использовать IPK пакеты, которые работают корректно:

```bash
cd /home/xendr4x/podkop-evolution

# Сборка IPK
docker build -f Dockerfile-ipk -t podkop:local-ipk \
    --build-arg PODKOP_VERSION="0.$(date +%d%m%Y)" .

# Извлечение пакетов
docker create --name podkop-ipk podkop:local-ipk
mkdir -p ./bin/ipk
docker cp podkop-ipk:/builder/bin/packages/x86_64/utilities/. ./bin/ipk/
docker cp podkop-ipk:/builder/bin/packages/x86_64/luci/. ./bin/ipk/
docker rm podkop-ipk

# Готово!
ls -lh ./bin/ipk/*.ipk
```

## Альтернатива: Сборка APK с сохранением артефактов

Если вам нужны именно APK пакеты, используйте этот метод:

```bash
cd /home/xendr4x/podkop-evolution

# Запустите сборку и сохраните промежуточный контейнер
docker build -f Dockerfile-apk -t podkop:build-apk \
    --build-arg PODKOP_VERSION="0.8.0" \
    --target builder \
    . 2>&1 | tee build.log

# Найдите ID последнего успешного слоя перед финальной очисткой
CONTAINER_ID=$(grep "Running in" build.log | tail -1 | awk '{print $3}')

# Скопируйте файлы из промежуточного контейнера
mkdir -p ./bin/apk
docker cp ${CONTAINER_ID}:/builder/bin/packages/x86_64/utilities/. ./bin/apk/ 2>/dev/null || true
docker cp ${CONTAINER_ID}:/builder/bin/packages/x86_64/luci/. ./bin/apk/ 2>/dev/null || true

ls -lh ./bin/apk/*.apk
```

## Исправление Dockerfile-apk (для разработчиков)

Чтобы исправить проблему, нужно изменить `Dockerfile-apk`:

```dockerfile
FROM itdoginfo/openwrt-sdk-apk:09102025 AS builder

ARG PODKOP_VERSION
ENV PODKOP_VERSION=${PODKOP_VERSION}

COPY ./podkop /builder/package/feeds/utilities/podkop
COPY ./luci-app-podkop /builder/package/feeds/luci/luci-app-podkop

RUN make defconfig && \
    make package/podkop/compile -j1 V=s && \
    make package/luci-app-podkop/compile -j1 V=s

# Сохраняем собранные пакеты
FROM scratch AS export
COPY --from=builder /builder/bin/packages/x86_64/ /packages/

# Или используйте финальный образ с пакетами
FROM alpine:latest
COPY --from=builder /builder/bin/packages/x86_64/ /packages/
CMD ["sh", "-c", "ls -la /packages/"]
```

Затем собирайте так:

```bash
docker build -f Dockerfile-apk --target export -o ./bin/apk .
```

## Быстрый скрипт для IPK

Создайте файл `build-ipk.sh`:

```bash
#!/bin/bash
set -e

VERSION="${1:-0.$(date +%d%m%Y)}"
echo "Building IPK packages, version: $VERSION"

docker build -f Dockerfile-ipk -t podkop:local-ipk \
    --build-arg PODKOP_VERSION="$VERSION" .

docker create --name podkop-ipk podkop:local-ipk
mkdir -p ./bin/ipk
docker cp podkop-ipk:/builder/bin/packages/x86_64/utilities/. ./bin/ipk/
docker cp podkop-ipk:/builder/bin/packages/x86_64/luci/. ./bin/ipk/
docker rm podkop-ipk

echo ""
echo "✅ Build complete! Packages:"
ls -lh ./bin/ipk/*.ipk
```

Использование:

```bash
chmod +x build-ipk.sh
./build-ipk.sh          # Автоматическая версия
./build-ipk.sh 0.8.0    # Кастомная версия
```

## Установка на роутер

IPK пакеты устанавливаются так же, как и APK:

```bash
# Скопируйте на роутер
scp ./bin/ipk/*.ipk root@192.168.1.1:/tmp/

# Установите
ssh root@192.168.1.1
cd /tmp
opkg install podkop*.ipk
opkg install luci-app-podkop*.ipk
opkg install luci-i18n-podkop-ru*.ipk  # опционально
/etc/init.d/podkop restart
```

## Заключение

- **Для локальной разработки**: используйте IPK (работает из коробки)
- **Для production**: GitHub Actions собирает оба формата (IPK и APK) корректно
- **APK локально**: требует модификации Dockerfile или использования промежуточных контейнеров
