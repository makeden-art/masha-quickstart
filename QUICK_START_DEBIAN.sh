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
echo "🖨️  Шаг 3: Установка и настройка CUPS на хост..."
if ! command -v lpstat &> /dev/null; then
    apt install -y cups cups-client cups-browsed
    echo "✅ CUPS установлен"
else
    echo "✅ CUPS уже установлен"
fi

# Настройка CUPS для доступа извне
if [ -f /etc/cups/cupsd.conf ]; then
    # Делаем резервную копию
    cp /etc/cups/cupsd.conf /etc/cups/cupsd.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # Изменяем Listen на все интерфейсы
    sed -i 's/^Listen localhost:631/Listen *:631/' /etc/cups/cupsd.conf
    
    # Разрешаем доступ извне в секции Location /
    if ! grep -q "Allow From All" /etc/cups/cupsd.conf; then
        python3 << 'PYEOF'
import re
with open('/etc/cups/cupsd.conf', 'r') as f:
    content = f.read()
pattern = r'<Location />.*?</Location>'
replacement = '''<Location />
  Order allow,deny
  Allow From All
</Location>'''
new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)
with open('/etc/cups/cupsd.conf', 'w') as f:
    f.write(new_content)
PYEOF
    fi
    
    echo "✅ CUPS настроен для доступа извне"
fi

systemctl enable cups
systemctl restart cups 2>/dev/null || systemctl start cups
sleep 2
echo "✅ CUPS запущен на хосте"

echo ""
echo "📁 Шаг 4: Создание директорий..."
mkdir -p $WORK_DIR/{config}
mkdir -p $DATA_DIR/{uploads,print_queue,split_pdfs,printed_archive}
touch $WORK_DIR/license.lic
chmod 644 $WORK_DIR/license.lic
chmod -R 755 $WORK_DIR
chmod -R 755 $DATA_DIR
# Убеждаемся, что printed_archive существует и имеет правильные права
chmod 755 $DATA_DIR/printed_archive
echo "✅ Директории созданы"

echo ""
echo "📝 Шаг 5: Создание docker-compose.yml..."
cat > $WORK_DIR/docker-compose.yml << EOF
services:
  masha:
    image: ${DOCKER_USERNAME}/masha-client:latest
    container_name: masha-print
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config:/app/config:rw
      # Статические файлы уже упакованы в образ
      # - ./static:/app/static:ro
      - ./license.lic:/app/license.lic:rw
      - ${DATA_DIR}/uploads:/app/uploads
      - ${DATA_DIR}/print_queue:/app/print_queue
      - ${DATA_DIR}/split_pdfs:/app/split_pdfs
      - ${DATA_DIR}/printed_archive:/app/printed_archive
    environment:
      - PYTHONUNBUFFERED=1
      - TZ=Europe/Moscow
      - REDIS_AVAILABLE=false
      - CUPS_SERVER=localhost
    healthcheck:
      test: ["CMD", "python3", "-c", "import requests; requests.get('http://localhost:8000/api/license/status', timeout=5)"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
echo "✅ docker-compose.yml создан"

echo ""
echo "📥 Шаг 6: Загрузка образа Docker..."
if [ "$DOCKER_USERNAME" = "YOUR_DOCKERHUB_USERNAME" ]; then
    echo "⚠️  ВНИМАНИЕ: Замените YOUR_DOCKERHUB_USERNAME на ваш реальный логин!"
    echo "   Запустите: docker pull YOUR_DOCKERHUB_USERNAME/masha-client:latest"
else
    docker pull "$IMAGE"
    echo "✅ Образ загружен"
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
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo "   📡 CUPS Web:     http://${HOST_IP}:631"
    echo "   🖨️  Маша Web:     http://${HOST_IP}:8000"
    echo "   📊 API Status:   http://${HOST_IP}:8000/api/license/status"
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

