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

echo ""
echo "Build complete! Packages are in ./bin/$PACKAGE_TYPE/"
ls -lh ./bin/$PACKAGE_TYPE/*.$PACKAGE_TYPE
