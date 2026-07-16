#!/bin/bash

# Скрипт для сбора бэкапов MySQL, скриптов VM2 и выгрузки на GitHub
# ОС: Ubuntu 22.04 | Репозиторий: https://github.com
# Скрипт автоматически делает себя исполняемым при запуске

# Делаем текущий скрипт исполняемым на будущее
chmod +x "$0" 2>/dev/null

# Выход при возникновении любой ошибки
set -e

# Переменные путей
BASE_SCRIPTS_DIR="/home/berd/scripts"
TARGET_GIT_DIR="/home/berd/scripts/linux_VM2_server2"
MYSQL_BACKUP_SOURCE="/home/berd/scripts/mysql_backup"
MYSQL_BACKUP_DEST="$TARGET_GIT_DIR/mysql_backup_to git"
REPO_URL="git@github.com:AlexIridium/linux_VM2_server2.git"

echo "=== 1. Создание структуры директорий ==="
mkdir -p "$MYSQL_BACKUP_DEST"

echo "=== 2. Копирование бэкапов MySQL ==="
if [ -d "$MYSQL_BACKUP_SOURCE" ]; then
    # Копируем содержимое директории mysql_backup в mysql_backup_to git
    cp -r "$MYSQL_BACKUP_SOURCE"/. "$MYSQL_BACKUP_DEST/" 2>/dev/null || echo "Папка бэкапов пуста."
else
    echo "Предупреждение: Исходная директория $MYSQL_BACKUP_SOURCE не найдена."
fi

echo "=== 3. Копирование скриптов из $BASE_SCRIPTS_DIR ==="
# Находим все файлы в корне /home/berd/scripts/ и копируем их в корень linux_VM2_server2.
# Игнорируем поддиректории, чтобы избежать бесконечного рекурсивного копирования.
find "$BASE_SCRIPTS_DIR" -maxdepth 1 -type f -exec cp {} "$TARGET_GIT_DIR/" \;

# Корректируем права владельца, чтобы файлы принадлежали пользователю berd
chown -R berd:berd "$TARGET_GIT_DIR"

echo "=== 4. Инициализация Git и добавление в безопасные директории ==="
# Добавляем исключение безопасности, чтобы root мог пушить репозиторий berd без ошибок dubios ownership
sudo git config --global --add safe.directory "$TARGET_GIT_DIR"

cd "$TARGET_GIT_DIR"

# Инициализируем репозиторий, если он не был инициализирован ранее
if [ ! -d ".git" ]; then
    sudo git init
    sudo git -c core.sshCommand="ssh -o StrictHostKeyChecking=no" remote add origin "$REPO_URL" || sudo git remote set-url origin "$REPO_URL"
    sudo git branch -M main
fi

# Добавляем все файлы в индекс Git через sudo
sudo git add .

# Проверяем, есть ли изменения для коммита
if ! sudo git diff-index --quiet HEAD -- 2>/dev/null; then
    sudo git commit -m "Automated backup: mysql dumps and server2 scripts update"
    echo "=== 5. Выгрузка файлов на GitHub (Git Push) ==="
    # Отправка по SSH выполняется через sudo от лица root (используется привязанный ключ)
    sudo git -c core.sshCommand="ssh -o StrictHostKeyChecking=no" push -u origin main --force
else
    echo "Изменений не обнаружено. Репозиторий уже синхронизирован с GitHub."
fi

echo "=== Выгрузка на GitHub успешно завершена! ==="
