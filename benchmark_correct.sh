#!/bin/bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"

echo "==========================================
🔬 BENCHMARK HEAD vs GET COMPLET
📍 IP: $LOCAL_IP:$PORT
==========================================

Test sur quelques sites..."
echo ""
printf "%-30s | %-10s | %-10s | %-10s | %s\n" "SITE" "HEAD" "GET-RANGE" "GET-FULL" "ANALYSE"
echo "----------------------------------------------------------------------------------------"

cd "$ROOT" || exit 1

# Prendre les 20 premiers sites
for site in $(ls -d *.* 2>/dev/null | head -20); do
    # Test HEAD
    head_code=$(curl -sS -I \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Test GET avec range (comme dans live_head.sh)
    get_range_code=$(curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --range 0-1024 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Test GET complet (limité en taille)
    get_full_code=$(curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --max-filesize 10000 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Analyse
    if [[ "$head_code" == "200" ]] && [[ "$get_range_code" == "206" ]]; then
        analyse="✅ OK"
    elif [[ "$head_code" == "200" ]] && [[ "$get_full_code" =~ ^5 ]]; then
        analyse="⚠️ HEAD MENT!"
    elif [[ "$head_code" == "$get_full_code" ]]; then
        analyse="✓ Cohérent"
    else
        analyse="❓ Vérifier"
    fi
    
    # Couleur selon le vrai status
    if [[ "$get_full_code" == "200" ]]; then
        color_code="\033[0;32m$get_full_code\033[0m"  # Vert
    elif [[ "$get_full_code" =~ ^3 ]]; then
        color_code="\033[1;33m$get_full_code\033[0m"  # Jaune
    elif [[ "$get_full_code" =~ ^5 ]]; then
        color_code="\033[0;31m$get_full_code\033[0m"  # Rouge
    else
        color_code="$get_full_code"
    fi
    
    printf "%-30s | %-10s | %-10s | %-10b | %s\n" \
        "${site:0:29}" "$head_code" "$get_range_code" "$color_code" "$analyse"
done

echo ""
echo "📝 Légende:"
echo "   - HEAD: Requête HEAD (rapide)"
echo "   - GET-RANGE: GET avec range 0-1024 (rapide, retourne 206 si OK)"
echo "   - GET-FULL: GET complet pour le vrai code"
echo "   - 206 = Partial Content (normal avec range)"
echo ""
echo "💡 Recommandation:"
echo "   Si HEAD=200 et GET-RANGE=206 → Le site fonctionne"
echo "   Si HEAD=200 mais GET-FULL=500 → HEAD ment, utiliser GET"
echo ""
echo "✅ Test terminé"