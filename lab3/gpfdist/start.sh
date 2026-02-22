#!/bin/bash
# Starts gpfdist pointing at /data/csv on port 8080.
# gpfdist is part of Greenplum installation; source the env first.

set -e

GP_PATH="/usr/local/greenplum-db/greenplum_path.sh"

if [[ -f "$GP_PATH" ]]; then
    source "$GP_PATH"
else
    # Try versioned path
    for d in /usr/local/greenplum-db-*/greenplum_path.sh; do
        [[ -f "$d" ]] && source "$d" && break
    done
fi

echo "[gpfdist] Starting on port 8080, serving /data/csv ..."
exec gpfdist \
    -d /data/csv \
    -p 8080 \
    -l /tmp/gpfdist.log \
    -v
