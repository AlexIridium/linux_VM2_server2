#!/bin/bash

# Скрипт установки ELK Stack на Linux Server 22.04
# Сервер: 10.17.86.141

# Делаем скрипт исполняемым
chmod +x "$0"

# Установка переменных
ELK_DIR="/home/berd/elk"
ES_PACKAGE="elasticsearch_8.17.1_amd64-224190-db972d.deb"
FILEBEAT_PACKAGE="filebeat_8.17.1_amd64-224190-a5f894.deb"
KIBANA_PACKAGE="kibana_8.17.1_amd64-224190-42bf22.deb"
LOGSTASH_PACKAGE="logstash_8.17.1_amd64-224190-40c12c.deb"

echo "=========================================="
echo "Начинаем установку ELK Stack"
echo "=========================================="

# Функция проверки статуса сервиса
check_service() {
    local service=$1
    echo "Проверка статуса $service..."
    systemctl status $service --no-pager | head -20
    echo "----------------------------------------"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "Пожалуйста, запустите скрипт с правами root (sudo)"
    exit 1
fi

# Проверка наличия директории
if [ ! -d "$ELK_DIR" ]; then
    echo "Ошибка: Директория $ELK_DIR не найдена!"
    exit 1
fi

# Переход в директорию с пакетами
cd $ELK_DIR || exit 1

# Проверка наличия пакетов
for pkg in $ES_PACKAGE $FILEBEAT_PACKAGE $KIBANA_PACKAGE $LOGSTASH_PACKAGE; do
    if [ ! -f "$pkg" ]; then
        echo "Ошибка: Пакет $pkg не найден в $ELK_DIR!"
        exit 1
    fi
done

# Остановка возможных конфликтующих процессов
echo "Остановка возможных конфликтующих процессов..."
systemctl stop elasticsearch 2>/dev/null
systemctl stop kibana 2>/dev/null
systemctl stop logstash 2>/dev/null
systemctl stop filebeat 2>/dev/null
sleep 2

# Удаление старых пакетов (если они есть)
echo "Удаление старых пакетов..."
dpkg -r elasticsearch 2>/dev/null
dpkg -r kibana 2>/dev/null
dpkg -r logstash 2>/dev/null
dpkg -r filebeat 2>/dev/null
sleep 2

# Очистка блокировок dpkg
echo "Очистка блокировок dpkg..."
rm -f /var/lib/dpkg/lock-frontend
rm -f /var/lib/dpkg/lock
rm -f /var/cache/apt/archives/lock
dpkg --configure -a

# Создание необходимых директорий для логов
echo "Создание директорий для логов Elasticsearch..."
mkdir -p /var/log/elasticsearch
mkdir -p /var/lib/elasticsearch
chown -R elasticsearch:elasticsearch /var/log/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch

# Установка Elasticsearch
echo "Установка Elasticsearch..."
dpkg -i $ES_PACKAGE
if [ $? -ne 0 ]; then
    echo "Ошибка при установке Elasticsearch! Попытка исправить..."
    apt --fix-broken install -y
    dpkg -i $ES_PACKAGE
    if [ $? -ne 0 ]; then
        echo "Критическая ошибка при установке Elasticsearch!"
        exit 1
    fi
fi

# Установка JDK (если не установлен)
echo "Проверка и установка default-jdk..."
if ! command -v java &> /dev/null; then
    apt install default-jdk -y
else
    echo "JDK уже установлен"
fi

# Настройка JVM options для Elasticsearch
echo "Настройка JVM options для Elasticsearch..."
mkdir -p /etc/elasticsearch/jvm.options.d
cat > /etc/elasticsearch/jvm.options.d/jvm.options << 'EOF'
-Xms1g
-Xmx1g
EOF

# Исправление конфигурации логирования Elasticsearch
echo "Исправление конфигурации логирования Elasticsearch..."
cat > /etc/elasticsearch/log4j2.properties << 'EOF'
status = error

appender.console.type = Console
appender.console.name = console
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%m%n

appender.rolling.type = RollingFile
appender.rolling.name = rolling
appender.rolling.fileName = ${sys:es.logs.base_path}${sys:file.separator}${sys:es.logs.cluster_name}.log
appender.rolling.layout.type = PatternLayout
appender.rolling.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%.-10000m%n
appender.rolling.filePattern = ${sys:es.logs.base_path}${sys:file.separator}${sys:es.logs.cluster_name}-%d{yyyy-MM-dd}-%i.log.gz
appender.rolling.policies.type = Policies
appender.rolling.policies.time.type = TimeBasedTriggeringPolicy
appender.rolling.policies.time.interval = 1
appender.rolling.policies.time.modulate = true
appender.rolling.policies.size.type = SizeBasedTriggeringPolicy
appender.rolling.policies.size.size = 256MB
appender.rolling.strategy.type = DefaultRolloverStrategy
appender.rolling.strategy.fileIndex = nomax
appender.rolling.strategy.action.type = Delete
appender.rolling.strategy.action.basepath = ${sys:es.logs.base_path}
appender.rolling.strategy.action.condition.type = IfFileName
appender.rolling.strategy.action.condition.glob = ${sys:es.logs.cluster_name}-*
appender.rolling.strategy.action.condition.nested_condition.type = IfAccumulatedFileSize
appender.rolling.strategy.action.condition.nested_condition.exceeds = 2GB

rootLogger.level = info
rootLogger.appenderRef.console.ref = console
rootLogger.appenderRef.rolling.ref = rolling
EOF

# Получение пароля Elasticsearch из логов
echo "Извлечение пароля Elasticsearch..."
ES_PASSWORD=$(grep -oP 'password is : \K[^ ]+' /var/log/elasticsearch/elasticsearch.log 2>/dev/null | tail -1)
if [ -z "$ES_PASSWORD" ]; then
    echo "Пароль не найден в логах, попробуем сбросить..."
    ES_PASSWORD=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b 2>/dev/null | grep -oP 'New value: \K[^ ]+')
fi

# Настройка elasticsearch.yml
echo "Настройка elasticsearch.yml..."
cat > /etc/elasticsearch/elasticsearch.yml << 'EOF'
# ---------------------------------- Cluster -----------------------------------
cluster.name: elk-cluster

# ------------------------------------ Node ------------------------------------
node.name: node-1
node.roles: [master, data, ingest]

# ----------------------------------- Paths ------------------------------------
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

# ----------------------------------- Memory -----------------------------------
bootstrap.memory_lock: false

# ---------------------------------- Network -----------------------------------
network.host: 0.0.0.0
http.port: 9200

# --------------------------------- Discovery ----------------------------------
discovery.type: single-node

# ---------------------------------- Various -----------------------------------
action.destructive_requires_name: false

# ---------------------------- Security Settings --------------------------------
xpack.security.enabled: false
xpack.security.enrollment.enabled: false

xpack.security.http.ssl:
  enabled: false

xpack.security.transport.ssl:
  enabled: false
EOF

# Настройка прав для Elasticsearch
echo "Настройка прав для Elasticsearch..."
chown -R elasticsearch:elasticsearch /etc/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
chown -R elasticsearch:elasticsearch /var/log/elasticsearch

# Запуск Elasticsearch
echo "Запуск Elasticsearch..."
systemctl daemon-reload
systemctl enable --now elasticsearch.service
sleep 15
check_service elasticsearch

# Проверка, что Elasticsearch работает
if systemctl is-active --quiet elasticsearch; then
    echo "Elasticsearch успешно запущен"
else
    echo "Ошибка запуска Elasticsearch. Просмотр логов:"
    journalctl -u elasticsearch --no-pager -n 50
    echo ""
    echo "Проверка логов Elasticsearch:"
    tail -50 /var/log/elasticsearch/elk-cluster.log 2>/dev/null || echo "Лог-файл не найден"
    exit 1
fi

# Установка Kibana
echo "Установка Kibana..."
dpkg -i $KIBANA_PACKAGE
if [ $? -ne 0 ]; then
    echo "Ошибка при установке Kibana! Попытка исправить..."
    apt --fix-broken install -y
    dpkg -i $KIBANA_PACKAGE
    if [ $? -ne 0 ]; then
        echo "Критическая ошибка при установке Kibana!"
        exit 1
    fi
fi

# Настройка kibana.yml
echo "Настройка kibana.yml..."
cat > /etc/kibana/kibana.yml << 'EOF'
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.requestTimeout: 30000
EOF

# Запуск Kibana
echo "Запуск Kibana..."
systemctl daemon-reload
systemctl enable --now kibana.service
sleep 5
systemctl restart kibana
check_service kibana

# Установка Logstash
echo "Установка Logstash..."
# Очистка блокировок перед установкой Logstash
rm -f /var/lib/dpkg/lock-frontend
rm -f /var/lib/dpkg/lock
dpkg --configure -a

dpkg -i $LOGSTASH_PACKAGE
if [ $? -ne 0 ]; then
    echo "Ошибка при установке Logstash! Попытка исправить..."
    apt --fix-broken install -y
    dpkg -i $LOGSTASH_PACKAGE
    if [ $? -ne 0 ]; then
        echo "Критическая ошибка при установке Logstash!"
        exit 1
    fi
fi

# Настройка logstash.yml
echo "Настройка logstash.yml..."
cat > /etc/logstash/logstash.yml << 'EOF'
path.data: /var/lib/logstash
path.config: /etc/logstash/conf.d
config.reload.automatic: true
config.reload.interval: 3s
http.host: "0.0.0.0"
EOF

# Создание конфигурации Logstash для Nginx
echo "Создание конфигурации Logstash для Nginx..."
mkdir -p /etc/logstash/conf.d
cat > /etc/logstash/conf.d/logstash-nginx-es.conf << 'EOF'
input {
    beats {
        port => 5400
    }
}

filter {
    grok {
        match => [ "message" , "%{COMBINEDAPACHELOG}+%{GREEDYDATA:extra_fields}"]
        overwrite => [ "message" ]
    }
    mutate {
        convert => ["response", "integer"]
        convert => ["bytes", "integer"]
        convert => ["responsetime", "float"]
    }
    date {
        match => [ "timestamp" , "dd/MMM/YYYY:HH:mm:ss Z" ]
        remove_field => [ "timestamp" ]
    }
    useragent {
        source => "agent"
    }
}

output {
    elasticsearch {
        hosts => ["http://localhost:9200"]
        index => "weblogs-%{+YYYY.MM.dd}"
        document_type => "nginx_logs"
    }
    stdout { codec => rubydebug }
}
EOF

# Настройка прав для Logstash
chown -R logstash:logstash /etc/logstash
chown -R logstash:logstash /var/lib/logstash
chown -R logstash:logstash /var/log/logstash

# Запуск Logstash
echo "Запуск Logstash..."
systemctl daemon-reload
systemctl enable --now logstash.service
sleep 5
systemctl restart logstash.service
check_service logstash

# Установка Filebeat
echo "Установка Filebeat..."
dpkg -i $FILEBEAT_PACKAGE
if [ $? -ne 0 ]; then
    echo "Ошибка при установке Filebeat! Попытка исправить..."
    apt --fix-broken install -y
    dpkg -i $FILEBEAT_PACKAGE
    if [ $? -ne 0 ]; then
        echo "Критическая ошибка при установке Filebeat!"
        exit 1
    fi
fi

# Настройка filebeat.yml
echo "Настройка filebeat.yml..."
cat > /etc/filebeat/filebeat.yml << 'EOF'
filebeat.inputs:
- type: filestream
  id: nginx-logs
  enabled: true
  paths:
    - /var/log/nginx/*.log
  exclude_files: ['.gz$']
  prospector.scanner.exclude_files: ['.gz$']

filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false

setup.template.settings:
  index.number_of_shards: 1

output.logstash:
  hosts: ["localhost:5400"]

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - add_kubernetes_metadata: ~
EOF

# Запуск Filebeat
echo "Запуск Filebeat..."
systemctl daemon-reload
systemctl enable filebeat
systemctl restart filebeat
check_service filebeat

echo "=========================================="
echo "Установка ELK Stack завершена!"
echo "=========================================="
echo "Elasticsearch: http://10.17.86.141:9200"
echo "Kibana: http://10.17.86.141:5601"
echo "Logstash: порт 5400 (Beats input)"
echo "Filebeat: сбор логов Nginx"
echo ""
echo "Пароль Elasticsearch (если включена аутентификация): $ES_PASSWORD"
echo "=========================================="
echo "Проверьте статусы сервисов:"
echo "systemctl status elasticsearch"
echo "systemctl status kibana"
echo "systemctl status logstash"
echo "systemctl status filebeat"
echo "=========================================="
echo "Просмотр логов при проблемах:"
echo "journalctl -u elasticsearch -f"
echo "journalctl -u kibana -f"
echo "journalctl -u logstash -f"
echo "journalctl -u filebeat -f"
echo "=========================================="
