#!/bin/bash

# Скрипт для сбора бэкапов MySQL, скриптов VM2 и выгрузки на GitHub
# ОС: Ubuntu 22.04 | Репозиторий: https://github.com/AlexIridium/linux_VM2
# Скрипт автоматически делает себя исполняемым при запуске

# Делаем текущий скрипт исполняемым на будущее
chmod +x "$0" 2>/dev/null

# Выход при возникновении любой ошибки
set -e

# Переменные путей
BASE_SCRIPTS_DIR="/home/berd/scripts"
TARGET_GIT_DIR="/home/berd/scripts/linux_VM2"
MYSQL_BACKUP_SOURCE="/home/berd/scripts/mysql_backup"
MYSQL_BACKUP_DEST="$TARGET_GIT_DIR/mysql_backup_to git"
REPO_URL="git@github.com:AlexIridium/linux_VM2.git"

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
# Находим все файлы в корне /home/berd/scripts/ и копируем их в корень linux_VM2.
# За счет -maxdepth 1 мы копируем только файлы скриптов и полностью игнорируем
# поддиректории mysql_backup и саму целевую linux_VM2, исключая дублирование.
find "$BASE_SCRIPTS_DIR" -maxdepth 1 -type f -exec cp {} "$TARGET_GIT_DIR/" \;

# Корректируем права владельца, чтобы Git работал корректно
chown -R berd:berd "$TARGET_GIT_DIR"

echo "=== 4. Инициализация Git и отправка данных ==="
cd "$TARGET_GIT_DIR"

# Инициализируем репозиторий, если он не был инициализирован ранее
if [ ! -d ".git" ]; then
    git init
    git -c core.sshCommand="ssh -o StrictHostKeyChecking=no" remote add origin "$REPO_URL" || git remote set-url origin "$REPO_URL"
    git branch -M main
fi

# Добавляем все файлы в индекс Git (включая папку "mysql_backup_to git")
git add .

# Проверяем, есть ли изменения для коммита
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git commit -m "Automated backup: mysql dumps and VM2 scripts update"
    echo "=== 5. Выгрузка файлов на GitHub (Git Push) ==="
    # Отправка по SSH (используется сгенерированный ранее ключ root, добавленный в GitHub)
    git -c core.sshCommand="ssh -o StrictHostKeyChecking=no" push -u origin main --force
else
    echo "Изменений не обнаружено. Репозиторий уже синхронизирован с GitHub."
fi

echo "=== Выгрузка на GitHub успешно завершена! ==="
