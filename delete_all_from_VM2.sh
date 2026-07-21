#!/bin/bash

# Скрипт для полного удаления пакетов ELK stack, mysql и директории бэкапов
# ОС: Ubuntu 22.04
# Скрипт автоматически делает себя исполняемым при запуске

# Автоматически делаем текущий скрипт исполняемым
chmod +x "$0" 2>/dev/null

# Выход при критических ошибках
set -e

echo "=== 1. Остановка запущенных сервисов ==="
sys_stop() {
    sudo systemctl stop "$1" 2>/dev/null || true
    sudo systemctl disable "$1" 2>/dev/null || true
}
sys_stop "elasticsearch"
sys_stop "logstash"
sys_stop "kibana"
sys_stop "mysql"

echo "=== 2. Полное удаление пакетов из системы (Purge) ==="
# Удаляем пакеты вместе с их системными конфигурационными файлами
sudo apt purge -y elasticsearch logstash kibana \
                  mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*

# Автоматическое удаление неиспользуемых зависимостей и очистка кэша пакетов
sudo apt autoremove -y
sudo apt clean

echo "=== 3. Удаление остаточных конфигураций, логов и данных ==="
remove_dir() {
    if [ -d "$1" ] || [ -f "$1" ]; then
        echo "Удаление каталога: $1"
        sudo rm -rf "$1"
    fi
}

# Конфигурации в /etc
remove_dir "/etc/elasticsearch"
remove_dir "/etc/logstash"
remove_dir "/etc/kibana"
remove_dir "/etc/mysql"

# Данные и логи в /var и /usr/share
remove_dir "/var/lib/elasticsearch"
remove_dir "/var/lib/logstash"
remove_dir "/var/lib/kibana"
remove_dir "/var/lib/mysql"

remove_dir "/var/log/elasticsearch"
remove_dir "/var/log/logstash"
remove_dir "/var/log/kibana"
remove_dir "/var/log/mysql"

remove_dir "/usr/share/elasticsearch"
remove_dir "/usr/share/logstash"
remove_dir "/usr/share/kibana"

echo "=== 4. Удаление директории с бэкапами ==="
remove_dir "/home/berd/scripts/mysql_backup"

echo "=== Все компоненты ELK, MySQL и папка бэкапов успешно удалены с VM2! ==="
