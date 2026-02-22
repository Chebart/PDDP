#!/bin/bash
set -e

source /usr/local/greenplum-db/greenplum_path.sh
export MASTER_DATA_DIRECTORY=/data/master/gpseg-1
export PXF_HOME="/usr/local/pxf"

# Pre-populate known_hosts to avoid interactive SSH prompts
su gpadmin -c "
    ssh-keyscan -H gpmaster gpsegment1 gpsegment2 >> /home/gpadmin/.ssh/known_hosts 2>/dev/null
    chmod 644 /home/gpadmin/.ssh/known_hosts
"

# Write PXF JDBC server config
PXF_BASE="/data/pxf"
PXF_SERVER_DIR="$PXF_BASE/servers/postgres"
mkdir -p "$PXF_SERVER_DIR"

sed \
    -e "s|\${POSTGRES_HOST}|${POSTGRES_HOST}|g" \
    -e "s|\${POSTGRES_DB}|${POSTGRES_DB}|g" \
    -e "s|\${POSTGRES_USER}|${POSTGRES_USER}|g" \
    -e "s|\${POSTGRES_PASSWORD}|${POSTGRES_PASSWORD}|g" \
    -e "s|\${PXF_JDBC_FETCH_SIZE}|${PXF_JDBC_FETCH_SIZE}|g" \
    /tmp/pxf/jdbc_postgres_config.xml > "$PXF_SERVER_DIR/jdbc-site.xml"

# Download JDBC driver if not present
JDBC_JAR="$PXF_HOME/lib/postgresql-42.7.1.jar"
if [[ ! -f "$JDBC_JAR" ]]; then
    echo "[INFO] Downloading PostgreSQL JDBC driver..."
    mkdir -p "$(dirname "$JDBC_JAR")"
    wget -q -O "$JDBC_JAR" https://jdbc.postgresql.org/download/postgresql-42.7.1.jar
fi

# Fix PXF ownership on master only
chown -R gpadmin:gpadmin "$PXF_HOME"
chown -R gpadmin:gpadmin "/data/pxf"

# Sync PXF config to all segment hosts and verify it landed
su gpadmin -c "
    source /usr/local/greenplum-db/greenplum_path.sh
    export MASTER_DATA_DIRECTORY=/data/master/gpseg-1
    export PXF_HOME=/usr/local/pxf
    export PXF_BASE=/data/pxf
    export PATH=\"/usr/local/pxf/bin:\$PATH\"

    pxf cluster sync

    for host in gpsegment1 gpsegment2; do
        ssh \$host test -f /data/pxf/servers/postgres/jdbc-site.xml || {
            echo \"[ERROR] jdbc-site.xml missing on \$host after pxf cluster sync\"
            exit 1
        }
        echo \"[OK] jdbc-site.xml verified on \$host\"
    done
"

echo "[OK] PXF setup complete."