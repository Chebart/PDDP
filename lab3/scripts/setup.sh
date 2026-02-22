#!/bin/bash
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

GP_DB="${GP_DATABASE:-toystore}"
PSQL="docker exec -i -u gpadmin gpmaster /usr/local/greenplum-db/bin/psql -U gpadmin -d $GP_DB"

step() { echo; echo "── $* ──────────────────────────────────────"; }

step "1/4  Downloading dataset"
./scripts/download_data.sh

step "2/4  SSH keys"
./scripts/generate_ssh_keys.sh

step "3/4  Starting containers"
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

for seg in gpsegment1 gpsegment2; do
    docker exec -u root "$seg" chown -R gpadmin:gpadmin /usr/local/pxf
done

docker cp scripts/setup_pxf.sh gpmaster:/tmp/setup_pxf.sh
docker exec -u root gpmaster bash /tmp/setup_pxf.sh

$PSQL < sql/pxf_external_tables.sql
$PSQL < sql/gp_tables.sql

step "4/4  Starting gpfdist"
docker compose up -d gpfdist

echo "Waiting for gpfdist to be ready..."
until docker exec gpfdist pgrep gpfdist &>/dev/null; do
    sleep 3
done
echo "gpfdist is ready."

$PSQL < sql/gpfdist_external_table.sql

echo
echo "Configuration step is done!"