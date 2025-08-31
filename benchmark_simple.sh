#!/bin/bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"

echo "==========================================
🔬 BENCHMARK HEAD vs GET
📍 IP: $LOCAL_IP:$PORT
==========================================

Vérification du répertoire $ROOT..."

cd "$ROOT" || exit 1
echo "Contenu de $ROOT:"
ls -d *.* 2>/dev/null | head -10

echo ""
echo "Test sur quelques sites..."
echo "SITE | HEAD | GET | MATCH?"
echo "----------------------------------------"

# Prendre les 10 premiers sites
for site in $(ls -d *.* 2>/dev/null | head -10); do
    # Test HEAD
    head_code=$(curl -sS -I \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 5 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Test GET avec range
    get_code=$(curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 5 \
        --range 0-1024 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Comparer
    if [[ "$head_code" == "$get_code" ]]; then
        match="✓"
    else
        match="✗ DIFF!"
    fi
    
    printf "%-30s | %3s | %3s | %s\n" "${site:0:29}" "$head_code" "$get_code" "$match"
done

echo ""
echo "✅ Test terminé"