#!/bin/bash

# Скрипт для автоматической установки и настройки MySQL 8.0 (Replica)
# ОС: Ubuntu 22.04 | IP: 10.17.86.141 | Master IP: 10.17.86.172
# Скрипт автоматически делает себя исполняемым при запуске

# Делаем текущий скрипт исполняемым на будущее
chmod +x "$0" 2>/dev/null

# Выход при любой ошибке
set -e

echo "=== 1. Установка MySQL 8.0 ==="
sudo apt install -y mysql-server

echo "=== 2. Настройка конфигурационного файла mysqld.cnf ==="
CONFIG_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"

# Резервная копия оригинального конфига
sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Изменение bind-address для разрешения внешних подключений
sudo sed -i 's/^bind-address.*/bind-address            = 0.0.0.0/' "$CONFIG_FILE"
sudo sed -i 's/^mysqlx-bind-address.*/mysqlx-bind-address     = 0.0.0.0/' "$CONFIG_FILE"

# Добавление параметров репликации в секцию [mysqld]
sudo bash -c "cat >> $CONFIG_FILE" << 'EOF'

# --- Настройки MySQL Replica для репликации ---
server-id                = 2
log-bin                  = mysql-bin
relay-log                = relay-log-server
read-only                = ON
gtid-mode                = ON
enforce-gtid-consistency  = ON
log-replica-updates      = ON
EOF

echo "=== 3. Перезапуск службы MySQL ==="
sudo systemctl restart mysql
sudo systemctl enable mysql

echo "=== 4. Настройка прав для безопасного снятия бэкапов ==="
# Ожидание готовности СУБД к приему команд
sleep 3

# Для корректной работы mysqldump с параметром --source-data (или --master-data)
# пользователю, делающему бэкап, требуются права REPLICATION CLIENT и RELOAD.
# Выдаем их локальному root, чтобы скрипт бэкапа мог работать без ошибок.
sudo mysql -e "GRANT RELOAD, REPLICATION CLIENT, SHOW DATABASES, LOCK TABLES, PROCESS ON *.* TO 'root'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "=== 5. Настройка источника репликации и запуск ==="
# Принудительная остановка старой реплики (если была запущена), чтобы избежать ошибок
sudo mysql -e "STOP REPLICA;" 2>/dev/null || true

# Выполнение SQL-команд для привязки к Master-серверу (IP изменен на 10.17.86.172)
sudo mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='10.17.86.172', SOURCE_USER='wp_test', SOURCE_PASSWORD='0000', SOURCE_AUTO_POSITION = 1, GET_SOURCE_PUBLIC_KEY = 1;"
sudo mysql -e "START REPLICA;"

echo "=== 6. Текущий статус репликации ==="
sudo mysql -e "SHOW REPLICA STATUS\G"

echo "=== Установка и настройка Replica-сервера успешно завершена! ==="
