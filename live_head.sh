#!/usr/bin/env bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"
WORKER_URL="https://live-head.restless-dust-dcc3.workers.dev/push"
AUTH_TOKEN="oROyVhmcMQ3W1ZjGs3CV798g0UJ9I4kHEulDgb76Tzru8t"

POD_INFO=$(basename /mnt/www/update/infra*-group* 2>/dev/null | head -n1)
POD_INFO="${POD_INFO:-unknown}"

LOG_FILE="/mnt/www/update/log/live_head-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# Fonction pour tester un site
test_site() {
  local d="$1"
  read -r code time_total <<<"$(curl -sS \
    -H "Host: $d" -H "X-Forwarded-Proto: https" \
    --http1.1 --no-keepalive \
    --max-time 10 --connect-timeout 3 \
    --range 0-1024 \
    -o /dev/null \
    -w '%{http_code} %{time_total}' \
    "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000 0")"
  
  # Normaliser le code 206 en 200 (Partial Content = OK)
  [[ "$code" == "206" ]] && code="200"
  
  ms="$(awk -v t="$time_total" 'BEGIN{printf("%d", t*1000)}')"
  ts="$(date +%s%3N)"
  
  printf '{"site":"%s","status":%d,"ms":%d,"pod":"%s","ts":%d}\n' \
    "$d" "$code" "$ms" "$POD_INFO" "$ts"
}

export -f test_site
export LOCAL_IP PORT POD_INFO

# Test en parallèle (10 simultanés)
cd "$ROOT"
results_file="/tmp/live_head_results_$$"
ls -d *.* 2>/dev/null | xargs -P 2 -I {} bash -c 'test_site "{}"' > "$results_file"

# Construire le payload
results=()
while IFS= read -r line; do
  [[ -n "$line" ]] && results+=("$line")
done < "$results_file"
rm -f "$results_file"

# Envoi API
payload="[ $(IFS=,; echo "${results[*]}") ]"
if curl -sS -X POST "$WORKER_URL" \
  --http1.1 --no-keepalive \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$payload" >/dev/null 2>&1; then
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK - ${#results[@]} sites envoyés ($POD_INFO)" >> "$LOG_FILE"
  echo "${#results[@]} sites"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERREUR API - ${#results[@]} sites ($POD_INFO)" >> "$LOG_FILE"
  echo "Erreur API"
fi
