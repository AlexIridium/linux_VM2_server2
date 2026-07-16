#!/bin/bash

# Скрипт для создания потабличного бэкапа пользовательских баз данных
# ОС: Ubuntu 22.04 | IP: 10.17.86.141
# Скрипт автоматически делает себя исполняемым при запуске

# Делаем текущий скрипт исполняемым на будущее
chmod +x "$0" 2>/dev/null

# Выход при любой ошибке
set -e

# Переменные
BACKUP_DIR="/home/berd/scripts/mysql_backup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MYSQL_USER="root"

echo "=== 1. Создание директории для бэкапа ==="
mkdir -p "$BACKUP_DIR"

echo "=== 2. Выдача необходимых прав для mysqldump ==="
sudo mysql -e "GRANT RELOAD, REPLICATION CLIENT, SHOW DATABASES, LOCK TABLES, PROCESS ON *.* TO 'root'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "=== 3. Получение списка пользовательских баз данных ==="
DATABASES=$(sudo mysql -u "$MYSQL_USER" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|sys|mysql)")

if [ -z "$DATABASES" ]; then
    echo "Внимание: Пользовательские базы данных не найдены. Нечего бэкапить."
    exit 0
fi

echo "=== 4. Запуск потабличного резервного копирования ==="
for DB in $DATABASES; do
    echo "Обработка базы данных: $DB"
    
    # Получаем список таблиц в текущей базе
    TABLES=$(sudo mysql -u "$MYSQL_USER" -D "$DB" -e "SHOW TABLES;" | grep -v "Tables_in_" || true)
    
    # Защита от пустых баз данных: если таблиц нет, делаем только дамп схемы/структуры базы
    if [ -z "$TABLES" ]; then
        TARGET_FILE="$BACKUP_DIR/${DB}_schema_only_${TIMESTAMP}.sql"
        echo "  База данных пуста. Дамп структуры -> $TARGET_FILE"
        sudo mysqldump -u "$MYSQL_USER" \
            --source-data=2 \
            --skip-lock-tables \
            --single-transaction \
            --set-gtid-purged=COMMENTED \
            --no-data "$DB" > "$TARGET_FILE"
    else
        # Если таблицы есть, бэкапим их потаблично
        for TABLE in $TABLES; do
            TARGET_FILE="$BACKUP_DIR/${DB}_${TABLE}_${TIMESTAMP}.sql"
            echo "  Дамп таблицы: $TABLE -> $TARGET_FILE"
            
            sudo mysqldump -u "$MYSQL_USER" \
                --source-data=2 \
                --skip-lock-tables \
                --single-transaction \
                --set-gtid-purged=COMMENTED \
                "$DB" "$TABLE" > "$TARGET_FILE"
        done
    fi
done

# Выставляем права, чтобы пользователь berd мог управлять файлами
sudo chown -R berd:berd "/home/berd/scripts"

echo "=== 5. Проверка созданных файлов в $BACKUP_DIR ==="
ls -lh "$BACKUP_DIR"

echo "=== 6. Проверка фиксации бинлога в файлах бэкапа ==="
# Отключаем 'set -e' временно, так как grep может вернуть код 1, если совпадений нет
set +e
BINLOG_CHECK=$(grep -h -E "CHANGE (REPLICATION SOURCE|MASTER TO)" "$BACKUP_DIR"/*.sql | head -n 5)
set -e

if [ -z "$BINLOG_CHECK" ]; then
    echo "ВНИМАНИЕ: Координаты бинлога НЕ найдены в файлах бэкапа!"
else
    echo "Координаты бинлога успешно зафиксированы:"
    echo "$BINLOG_CHECK"
fi

echo "=== Резервное копирование успешно завершено! ==="
