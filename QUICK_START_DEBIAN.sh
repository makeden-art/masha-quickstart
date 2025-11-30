#!/bin/bash
# Быстрый скрипт установки Маша Print Service на Debian 13

set -e

echo "🚀 Установка Маша Print Service на Debian 13"
echo "=========================================="

# Проверка root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запустите скрипт от root: sudo $0"
    exit 1
fi

# Переменные
DOCKER_USERNAME="${1:-YOUR_DOCKERHUB_USERNAME}"
WORK_DIR="/opt/masha-client"
DATA_DIR="/var/masha"
IMAGE="${DOCKER_USERNAME}/masha-client:latest"

if [ "$DOCKER_USERNAME" = "YOUR_DOCKERHUB_USERNAME" ]; then
    echo "❌ Укажите логин Docker Hub: ./QUICK_START_DEBIAN.sh <dockerhub_username>"
    exit 1
fi

echo ""
echo "📦 Шаг 1: Обновление системы..."
apt update && apt upgrade -y

echo ""
echo "🐳 Шаг 2: Установка Docker..."
if ! command -v docker &> /dev/null; then
    # Установка Docker
    apt install -y curl ca-certificates gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    echo "✅ Docker установлен"
else
    echo "✅ Docker уже установлен"
fi

echo ""
echo "📁 Шаг 3: Создание директорий..."
mkdir -p $WORK_DIR/{config}
mkdir -p $DATA_DIR/{uploads,print_queue,split_pdfs,cups,cups-spool}
touch $WORK_DIR/license.lic
chmod 644 $WORK_DIR/license.lic
chmod -R 755 $WORK_DIR
chmod -R 755 $DATA_DIR
echo "✅ Директории созданы"

echo ""
echo "📝 Шаг 4: Создание docker-compose.yml..."
cat > $WORK_DIR/docker-compose.yml << EOF
services:
  masha:
    image: ${DOCKER_USERNAME}/masha-client:latest
    container_name: masha-print
    restart: unless-stopped
    privileged: true
    ports:
      - "8000:8000"
      - "631:631"
    volumes:
      - ./config:/app/config:rw
      # Статические файлы уже упакованы в образ
      # - ./static:/app/static:ro
      - ./license.lic:/app/license.lic:rw
      - ${DATA_DIR}/uploads:/app/uploads
      - ${DATA_DIR}/print_queue:/app/print_queue
      - ${DATA_DIR}/split_pdfs:/app/split_pdfs
      - ${DATA_DIR}/cups:/etc/cups
      - ${DATA_DIR}/cups-spool:/var/spool/cups
    environment:
      - PYTHONUNBUFFERED=1
      - TZ=Europe/Moscow
      - REDIS_AVAILABLE=false
    healthcheck:
      test: ["CMD", "python3", "-c", "import requests; requests.get('http://localhost:8000/api/license/status', timeout=5)"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
echo "✅ docker-compose.yml создан"

echo ""
echo "📥 Шаг 5: Загрузка образа Docker..."
if [ "$DOCKER_USERNAME" = "YOUR_DOCKERHUB_USERNAME" ]; then
    echo "⚠️  ВНИМАНИЕ: Замените YOUR_DOCKERHUB_USERNAME на ваш реальный логин!"
    echo "   Запустите: docker pull YOUR_DOCKERHUB_USERNAME/masha-client:latest"
else
    docker pull "$IMAGE"
    echo "✅ Образ загружен"
fi

echo ""
echo "🧩 Шаг 6: Подготовка конфигурации CUPS..."
if [ "$DOCKER_USERNAME" != "YOUR_DOCKERHUB_USERNAME" ]; then
    docker run --rm --entrypoint sh "$IMAGE" -c 'cd /etc && tar cf - cups' | tar -C "$DATA_DIR" --numeric-owner -xf -
    docker run --rm --entrypoint sh "$IMAGE" -c 'cd /var && tar cf - spool/cups' | tar -C "$DATA_DIR" --numeric-owner -xf -
    chmod -R 755 "$DATA_DIR/cups" "$DATA_DIR/cups-spool"
    echo "✅ Конфигурация CUPS синхронизирована"
else
    echo "⚠️  Пропускаю (нет имени образа). После запуска скопируйте конфиги вручную."
fi

echo ""
echo "🚀 Шаг 7: Запуск контейнера..."
cd $WORK_DIR
docker compose up -d

echo ""
echo "⏳ Ожидание запуска (10 секунд)..."
sleep 10

echo ""
echo "📊 Шаг 8: Проверка статуса..."
if docker ps | grep -q masha-print; then
    echo "✅ Контейнер запущен!"
    echo ""
    echo "🌐 Доступные интерфейсы:"
    echo "   📡 CUPS Web:     http://$(hostname -I | awk '{print $1}'):631"
    echo "   🖨️  Маша Web:     http://$(hostname -I | awk '{print $1}'):8000"
    echo "   📊 API Status:   http://$(hostname -I | awk '{print $1}'):8000/api/license/status"
    echo ""
    echo "📋 Полезные команды:"
    echo "   Логи:           docker logs -f masha-print"
    echo "   Статус:         docker ps | grep masha"
    echo "   Перезапуск:     cd $WORK_DIR && docker compose restart"
    echo "   Остановка:      cd $WORK_DIR && docker compose down"
else
    echo "❌ Контейнер не запущен. Проверьте логи:"
    echo "   docker logs masha-print"
    exit 1
fi

echo ""
echo "✅ Установка завершена!"

