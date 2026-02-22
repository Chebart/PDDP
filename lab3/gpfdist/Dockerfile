# ──────────────────────────────────────────────────────────────
# Dockerfile for gpfdist (Max task / Усложненный вариант)
#
# gpfdist is Greenplum's parallel file distribution utility.
# It serves CSV files over HTTP so each GP segment can pull
# data directly — all reads happen in parallel.
#
# Build context: lab3/gpfdist/
# CSV files are mounted from the host's ./data/ directory.
# ──────────────────────────────────────────────────────────────

FROM woblerr/greenplum:6.27.1

USER root

# Create directory for CSV files (will be bind-mounted at runtime)
RUN mkdir -p /data/csv && chown -R gpadmin:gpadmin /data/csv

# Copy the startup script
COPY start.sh /home/gpadmin/start.sh
RUN chmod +x /home/gpadmin/start.sh && chown gpadmin:gpadmin /home/gpadmin/start.sh

USER gpadmin

# Mount point: host ./data directory (CSV files)
VOLUME ["/data/csv"]

EXPOSE 8080

HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=5 \
    CMD pgrep gpfdist > /dev/null || exit 1

ENTRYPOINT ["/home/gpadmin/start.sh"]
