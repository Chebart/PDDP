#!/bin/bash
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

GP_DB="${GP_DATABASE:-toystore}"
PSQL="docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d $GP_DB"

step() { echo; echo "── $* ──────────────────────────────────────"; }

set -a; source "$BASE/.env"; set +a

step "1/5  Downloading dataset"
./scripts/download_data.sh

step "2/5  SSH keys"
sudo rm -rf greenplum/ssh/
./scripts/generate_ssh_keys.sh

step "3/5  PXF config"
sudo chown -R "$(id -u):$(id -g)" pxf_conf/ 2>/dev/null || true
JDBC_JAR="pxf_conf/lib/postgresql-42.7.1.jar"
if [[ ! -f "$JDBC_JAR" ]]; then
    echo "Downloading PostgreSQL JDBC driver..."
    wget -q -O "$JDBC_JAR" https://jdbc.postgresql.org/download/postgresql-42.7.1.jar
fi
envsubst < pxf_conf/servers/postgres/jdbc-site.xml.tmpl \
    > pxf_conf/servers/postgres/jdbc-site.xml
echo "PXF config ready."

step "4/5  Starting containers"
docker compose up -d postgres gpsegment1 gpsegment2

echo "Waiting for Postgres to be ready..."
until docker exec postgres_source pg_isready -U "${POSTGRES_USER:-postgres}" -d "$GP_DB" &>/dev/null; do
    sleep 3
done

docker compose up -d gpmaster
echo "Waiting 60s for Greenplum master to initialise..."
sleep 60

for i in $(seq 1 15); do
    $PSQL -c "SELECT 1" &>/dev/null && echo "Greenplum is ready." && break
    [[ $i -eq 15 ]] && { echo "ERROR: Greenplum master did not start. Check logs: docker logs gpmaster"; exit 1; }
    echo "  still waiting ($i/15)..."
    sleep 10
done

PXF_ENV="source /usr/local/greenplum-db/greenplum_path.sh
    export PATH=/usr/local/pxf/bin:\$PATH
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
    export MASTER_DATA_DIRECTORY=/data/master/gpseg-1
    export PXF_BASE=/data/pxf"

docker exec -u gpadmin gpmaster bash -c "$PXF_ENV && pxf cluster prepare"
docker exec -u gpadmin gpmaster mkdir -p /data/pxf/servers/postgres /data/pxf/lib
docker cp pxf_conf/servers/postgres/jdbc-site.xml gpmaster:/data/pxf/servers/postgres/jdbc-site.xml
docker cp pxf_conf/lib/postgresql-42.7.1.jar     gpmaster:/data/pxf/lib/postgresql-42.7.1.jar
docker exec -u gpadmin gpmaster bash -c "$PXF_ENV && pxf cluster sync && pxf cluster start"

$PSQL < sql/pxf_external_tables.sql
$PSQL < sql/gp_tables.sql

step "5/5  Starting gpfdist"
docker compose up -d gpfdist

echo "Waiting for gpfdist to be ready..."
until docker exec gpfdist pgrep gpfdist &>/dev/null; do
    sleep 3
done
echo "gpfdist is ready."

$PSQL < sql/gpfdist_external_table.sql

echo
echo "Configuration step is done!"