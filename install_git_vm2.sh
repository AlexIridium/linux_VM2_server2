#!/bin/bash

# Скрипт для установки Git и генерации SSH-ключа Ed25519 на VM2
# ОС: Ubuntu 22.04 | Имя: Alex | Email: berdnikow.ksit@mail.ru

# Автоматически делаем текущий скрипт исполняемым
chmod +x "$0" 2>/dev/null

# Выход при возникновении любой ошибки
set -e

echo "=== 1. Установка Git ==="
apt install git -y

echo "=== 2. Настройка глобальных параметров Git ==="
git config --global user.name "Alex"
git config --global user.email "berdnikow.ksit@mail.ru"

echo "=== 3. Проверка текущих настроек Git ==="
git config --list

echo "=== 4. Генерация SSH-ключа Ed25519 для пользователя root ==="
# -N "" задает пустой пароль, -f указывает путь для автоматической генерации
if [ ! -f /root/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
else
    echo "SSH-ключ уже существует, генерация пропущена."
fi

echo "=== 5. Отображение публичного SSH-ключа ==="
echo "-----------------------------------------------------------------"
cat /root/.ssh/id_ed25519.pub
echo "-----------------------------------------------------------------"

echo "=== Скрипт install_git_vm2.sh успешно выполнен! ==="
