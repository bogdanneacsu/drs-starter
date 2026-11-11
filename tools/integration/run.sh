#!/usr/bin/env bash
# Local integration test: real Laravel (php artisan serve, sqlite dev DB) ↔ real DRS Starter Lua client modules.
# Usage: tools/integration/run.sh <path-to-drs_v2-copy>   (from the drs_start_app folder; needs php, luajit, curl)
# Never point it at a production checkout/database: it creates database/starter_integration.sqlite and uses it.
set -euo pipefail
ROOT="$(cd "$1" && pwd)"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
DB="$ROOT/database/starter_integration.sqlite"
PORT="${PORT:-8765}"
export APP_ENV=local APP_DEBUG=false DB_CONNECTION=sqlite DB_DATABASE="$DB" CACHE_STORE=array SESSION_DRIVER=array QUEUE_CONNECTION=sync MAIL_MAILER=array
export APP_KEY="${APP_KEY:-base64:$(head -c 32 /dev/urandom | base64)}"
rm -f "$DB"; touch "$DB"
(cd "$ROOT" && php artisan migrate --force -q)
SEED=$(php "$HERE/tools/integration/laravel.php" "$ROOT" seed)
(cd "$ROOT" && php artisan serve --port="$PORT" -q > /tmp/starter_integration_server.log 2>&1) &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; pkill -f "artisan serve --port=$PORT" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/up" && break; sleep 0.2; done
cd "$HERE"
BASE="http://127.0.0.1:$PORT" LARAVEL_ROOT="$ROOT" SEED="$SEED" luajit tests/integration_laravel.lua
echo "--- server-side slots ---"
php "$HERE/tools/integration/laravel.php" "$ROOT" state
