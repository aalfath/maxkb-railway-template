#!/bin/bash
# Railway start script for MaxKB (aalfath/maxkb-railway-template).
# Replaces the image's start-all.sh, which also runs a bundled PostgreSQL and Redis.
set -euo pipefail
log() { echo "railway-start: $*"; }
die() { echo "railway-start: ERROR: $*" >&2; exit 1; }

# ---- required settings (all come from the template's references) ----
for v in MAXKB_DB_HOST MAXKB_DB_NAME MAXKB_DB_USER MAXKB_DB_PASSWORD MAXKB_REDIS_HOST MAXKB_REDIS_PASSWORD MAXKB_SECRET_KEY MAXKB_DEFAULT_PASSWORD; do
  [ -n "${!v:-}" ] || die "$v is empty. Set it on the MaxKB service (see the template README)."
done
[ "$MAXKB_DB_HOST" != "127.0.0.1" ] || die "MAXKB_DB_HOST must point at the Postgres service, not the bundled database."
[ "$MAXKB_REDIS_HOST" != "127.0.0.1" ] || die "MAXKB_REDIS_HOST must point at the Redis service, not the bundled Redis."

# ---- defaults suited to a small Railway container ----
export MAXKB_DB_PORT="${MAXKB_DB_PORT:-5432}"
export MAXKB_REDIS_PORT="${MAXKB_REDIS_PORT:-6379}"
export MAXKB_HTTP_LISTEN_PORT="${PORT:-8080}"
export MAXKB_LANGUAGE_CODE="${MAXKB_LANGUAGE_CODE:-en-US}"
export MAXKB_TIME_ZONE="${MAXKB_TIME_ZONE:-UTC}"
# Upstream starts 3 gunicorn workers (200 threads each) whenever the host has more than
# 6 CPUs, which Railway always reports. One worker fits Railway's smaller plans.
export MAXKB_CORE_WORKER="${MAXKB_CORE_WORKER:-1}"
# Pool of 20 + overflow for each of the 3 processes; keep the total under Postgres max_connections (100).
export MAXKB_DB_MAX_OVERFLOW="${MAXKB_DB_MAX_OVERFLOW:-5}"
export MAXKB_REDIS_MAX_CONNECTIONS="${MAXKB_REDIS_MAX_CONNECTIONS:-50}"
# Cap math-library threads to the container, not the host (the local embedding model uses torch).
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}" MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}" \
       OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}" TOKENIZERS_PARALLELISM=false
# Tool code runs in upstream's sandbox; also keep it off Railway's private network
# (Postgres, Redis and any other service in the project).
export MAXKB_SANDBOX_PYTHON_BANNED_HOSTS="${MAXKB_SANDBOX_PYTHON_BANNED_HOSTS:-127.0.0.0/8,localhost,host.docker.internal,172.17.0.0/16,maxkb,pgsql,redis,172.31.250.192/26,0.0.0.0/32,::/0,10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,.*[.]railway[.]internal}"

# ---- wait for Postgres and enable pgvector ----
export PGPASSWORD="$MAXKB_DB_PASSWORD" PGCONNECT_TIMEOUT=5
i=0
until psql -h "$MAXKB_DB_HOST" -p "$MAXKB_DB_PORT" -U "$MAXKB_DB_USER" -d "$MAXKB_DB_NAME" -v ON_ERROR_STOP=1 -qc 'CREATE EXTENSION IF NOT EXISTS vector' >/dev/null 2>/tmp/pg.err; do
  i=$((i+1)); [ "$i" -lt 60 ] || { cat /tmp/pg.err >&2; die "Postgres not ready after 5 minutes"; }
  log "waiting for Postgres ($i/60): $(head -c 200 /tmp/pg.err | tr '\n' ' ')"; sleep 5
done
unset PGPASSWORD
log "Postgres ready, pgvector enabled"

# ---- volume layout (same as upstream start-maxkb.sh) ----
mkdir -p /opt/maxkb/logs /opt/maxkb/local /opt/maxkb/python-packages
chmod 700 /opt/maxkb/logs /opt/maxkb/local
mkdir -p /opt/maxkb-app/tmp && chmod 700 /opt/maxkb-app/tmp
rm -f /opt/maxkb-app/tmp/* 2>/dev/null || true

# ---- migrations, one deploy at a time (overlapping deploys share the database) ----
cd /opt/maxkb-app
python - <<'PY' || die "database migration failed"
import os, subprocess, sys, psycopg
c = psycopg.connect(host=os.environ["MAXKB_DB_HOST"], port=os.environ["MAXKB_DB_PORT"],
                    dbname=os.environ["MAXKB_DB_NAME"], user=os.environ["MAXKB_DB_USER"],
                    password=os.environ["MAXKB_DB_PASSWORD"], autocommit=True)
c.execute("SELECT pg_advisory_lock(2906001)")
print("railway-start: migration lock held, running migrations", flush=True)
r = subprocess.run([sys.executable, "/opt/maxkb-app/main.py", "upgrade_db"])
c.execute("SELECT pg_advisory_unlock(2906001)"); c.close()
sys.exit(r.returncode)
PY
log "migrations done"

# ---- upstream's optional init shells ----
_INIT_SHELL_DIR=${MAXKB_INIT_SHELL_DIR:-/opt/maxkb/local/init-shells}
if [ -d "$_INIT_SHELL_DIR" ]; then
  find "$_INIT_SHELL_DIR" -maxdepth 1 -type f -name "*.sh" | sort | while IFS= read -r f; do
    bash "$f" && log "init-shell ok: $f" || log "init-shell failed: $f"
  done
fi

# ---- start MaxKB (web, local model server, task worker) ----
# Upstream's supervisor writes each process's output to /opt/maxkb/logs/*.log;
# mirror those to stdout so they show in Railway's logs.
touch /opt/maxkb/logs/gunicorn.log /opt/maxkb/logs/celery_default.log /opt/maxkb/logs/local_model.log
tail -q -n0 -F /opt/maxkb/logs/gunicorn.log /opt/maxkb/logs/celery_default.log /opt/maxkb/logs/local_model.log 2>/dev/null &
tail_pid=$!

stopping=0
python /opt/maxkb-app/main.py start all &
app_pid=$!
# SIGINT makes upstream's supervisor stop its processes cleanly.
trap 'stopping=1; log "stopping"; kill -INT "$app_pid" 2>/dev/null || true' TERM INT
set +e
wait "$app_pid"; rc=$?
while [ "$stopping" = 1 ] && kill -0 "$app_pid" 2>/dev/null; do wait "$app_pid"; rc=$?; done
kill "$tail_pid" 2>/dev/null
if [ "$stopping" = 1 ]; then log "stopped"; exit 0; fi
# Upstream's supervisor exits 0 when a process dies for good; make Railway restart us.
echo "railway-start: ERROR: MaxKB exited unexpectedly (code $rc)" >&2
exit 1
