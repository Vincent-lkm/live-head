#!/usr/bin/env bash
set -euo pipefail

# Configuration
ROOT="/mnt/www"
PORT="${PORT:-8080}"
LOCAL_IP="$(hostname -i | awk '{print $1}')"
WORKER_URL="${WORKER_URL:?set WORKER_URL}"
AUTH_TOKEN="${AUTH_TOKEN:?set AUTH_TOKEN}"
IGNORE_REGEX='^(update|backups|readyz|new|lost\+found)$'

# Extraction de l'info pod (infra-group)
POD_INFO=$(basename /mnt/www/update/infra*-group* 2>/dev/null | head -n1)
POD_INFO="${POD_INFO:-unknown}"  # Fallback si pas trouvé

results=()

probe_one() {
  local site="$1"
  local url="http://${LOCAL_IP}:${PORT}/"
  local tmp="$(mktemp)"

  # Tentative HEAD d'abord
  read -r code time_total <<<"$(curl -sS -I \
      -H "Host: ${site}" -H "X-Forwarded-Proto: https" \
      --max-time 10 --connect-timeout 3 \
      -o /dev/null -D "$tmp" \
      -w '%{http_code} %{time_total}' \
      "$url" || echo "000 0")"

  # Fallback GET si HEAD échoue/refuse
  if [[ "$code" == "000" || "$code" == "405" || "$code" == "400" ]]; then
    : > "$tmp"
    read -r code time_total <<<"$(curl -sS \
        -H "Host: ${site}" -H "X-Forwarded-Proto: https" \
        --max-time 10 --connect-timeout 3 \
        --range 0-0 -X GET \
        -o /dev/null -D "$tmp" \
        -w '%{http_code} %{time_total}' \
        "$url" || echo "000 0")"
  fi

  # Extraction redirect location si 3xx
  local location=""
  if [[ "$code" =~ ^30(1|2|7|8)$ ]]; then
    location="$(awk '/^Location:/ {sub(/\r$/,"",$0); print $2; exit}' "$tmp")"
  fi
  rm -f "$tmp"

  # Conversion en millisecondes + timestamp
  local ms; ms="$(awk -v t="$time_total" 'BEGIN{printf("%d", t*1000)}')"
  local ts; ts="$(date +%s%3N)"

  # Construction JSON avec pod info
  if [[ -n "$location" ]]; then
    results+=("$(printf '{"site":"%s","status":%d,"ms":%d,"pod":"%s","redir":"%s","ts":%d}' \
      "$site" "$code" "$ms" "$POD_INFO" "$location" "$ts")")
  else
    results+=("$(printf '{"site":"%s","status":%d,"ms":%d,"pod":"%s","ts":%d}' \
      "$site" "$code" "$ms" "$POD_INFO" "$ts")")
  fi
}

# Scan tous les répertoires (= sites)
cd "$ROOT"
for d in *; do
  [[ -d "$d" ]] || continue
  [[ "$d" =~ $IGNORE_REGEX ]] && continue
  probe_one "$d"
done

# Envoi batch vers Cloudflare
payload="[ $(IFS=,; echo "${results[*]}") ]"

curl -sS -X POST "$WORKER_URL" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$payload" >/dev/null