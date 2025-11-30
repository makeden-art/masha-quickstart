#!/bin/bash
# Скрипт для полной очистки установки Masha Print Service на Debian

set -e

echo "🧹 Очистка Masha Print Service"
echo "=============================="

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите скрипт от root: sudo $0"
    exit 1
fi

WORK_DIR="/opt/masha-client"
DATA_DIR="/var/masha"
CONTAINER="masha-print"
COMPOSE_FILE="$WORK_DIR/docker-compose.yml"

echo "📦 Остановка контейнера..."
if [ -f "$COMPOSE_FILE" ]; then
    docker compose -f "$COMPOSE_FILE" down || true
else
    docker stop "$CONTAINER" 2>/dev/null || true
    docker rm "$CONTAINER" 2>/dev/null || true
fi

echo "🗑️  Удаление образа..."
docker rmi makeden/masha-client:latest 2>/dev/null || true

echo "🧾 Удаление рабочих директорий..."
rm -rf "$WORK_DIR"
rm -rf "$DATA_DIR"

echo "📦 Удаление сетей Docker..."
docker network rm masha-client_default 2>/dev/null || true

echo "🧰 Очистка зависимостей (Docker оставлен установленным)"

echo "✅ Очистка завершена"





