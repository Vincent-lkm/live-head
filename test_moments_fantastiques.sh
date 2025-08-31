#!/bin/bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"

echo "=========================================="
echo "🔬 TEST AVEC moments-fantastiques.fr"
echo "📍 IP: $LOCAL_IP:$PORT"
echo "=========================================="
echo ""

printf "%-30s | %-6s | %-10s | %-8s | %s\n" "SITE" "HEAD" "GET-RANGE" "GET-FULL" "DIAGNOSTIC"
echo "------------------------------------------------------------------------------------"

cd "$ROOT" || exit 1

# Liste de sites incluant moments-fantastiques.fr
sites=(
    "moments-fantastiques.fr"
    "amenagementlogement.fr"
    "analyse-et-finance.fr"
    "aventuredecouverte.fr"
    "banque-investissement.fr"
    "chateaux-historiques.fr"
    "astuceconstructeur.fr"
    "caps-decouverts.fr"
    "astucesdebricolage.fr"
    "amenagementmoderne.fr"
)

# Tester chaque site
for site in "${sites[@]}"; do
    # Vérifier que le site existe
    if [[ ! -d "$site" ]]; then
        printf "%-30s | %-6s | %-10s | %-8s | %s\n" \
            "${site:0:29}" "---" "---" "---" "❌ Pas trouvé"
        continue
    fi
    
    # Test HEAD (rapide)
    head_time_start=$(date +%s%N)
    head_code=$(curl -sS -I \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 5 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    head_time=$(($(date +%s%N) - head_time_start))
    head_ms=$((head_time / 1000000))
    
    # Test GET avec range
    range_time_start=$(date +%s%N)
    get_range_code=$(curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 5 \
        --range 0-1024 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    range_time=$(($(date +%s%N) - range_time_start))
    range_ms=$((range_time / 1000000))
    
    # Test GET complet (pour voir le vrai code)
    full_time_start=$(date +%s%N)
    get_full_code=$(curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 5 \
        --max-filesize 50000 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    full_time=$(($(date +%s%N) - full_time_start))
    full_ms=$((full_time / 1000000))
    
    # Diagnostic
    if [[ "$site" == "moments-fantastiques.fr" ]]; then
        # Analyse spéciale pour moments-fantastiques.fr
        if [[ "$head_code" == "200" ]] && [[ "$get_full_code" =~ ^5 ]]; then
            diagnostic="🔴 HEAD MENT! (200→500)"
            color_site="\033[1;31m${site:0:29}\033[0m"  # Rouge
        else
            diagnostic="🟢 Corrigé?"
            color_site="${site:0:29}"
        fi
    elif [[ "$head_code" == "200" ]] && [[ "$get_range_code" == "206" ]] && [[ "$get_full_code" == "200" ]]; then
        diagnostic="✅ OK"
        color_site="${site:0:29}"
    elif [[ "$head_code" == "200" ]] && [[ "$get_full_code" =~ ^5 ]]; then
        diagnostic="⚠️ HEAD MENT!"
        color_site="\033[1;33m${site:0:29}\033[0m"  # Jaune
    elif [[ "$get_full_code" =~ ^5 ]]; then
        diagnostic="❌ Erreur 5xx"
        color_site="\033[0;31m${site:0:29}\033[0m"  # Rouge
    else
        diagnostic="✓ OK"
        color_site="${site:0:29}"
    fi
    
    # Affichage avec temps
    printf "%-30b | %3s%-3s | %3s%-7s | %3s%-5s | %s\n" \
        "$color_site" \
        "$head_code" "(${head_ms}ms)" \
        "$get_range_code" "(${range_ms}ms)" \
        "$get_full_code" "(${full_ms}ms)" \
        "$diagnostic"
done

echo "------------------------------------------------------------------------------------"
echo ""
echo "📊 ANALYSE moments-fantastiques.fr:"
echo ""

# Test détaillé pour moments-fantastiques.fr
if [[ -d "moments-fantastiques.fr" ]]; then
    echo "Test approfondi..."
    
    # Test avec différentes méthodes
    echo ""
    echo "1️⃣ Test HEAD:"
    curl -I -H "Host: moments-fantastiques.fr" -H "X-Forwarded-Proto: https" \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null | head -3
    
    echo ""
    echo "2️⃣ Test GET avec range (début de la réponse):"
    curl -sS -H "Host: moments-fantastiques.fr" -H "X-Forwarded-Proto: https" \
        --range 0-500 "http://${LOCAL_IP}:${PORT}/" 2>/dev/null | head -5
    
    echo ""
    echo "3️⃣ Test GET complet (début de la réponse):"
    curl -sS -H "Host: moments-fantastiques.fr" -H "X-Forwarded-Proto: https" \
        --max-time 2 "http://${LOCAL_IP}:${PORT}/" 2>&1 | head -10
else
    echo "❌ moments-fantastiques.fr non trouvé dans /mnt/www"
fi

echo ""
echo "💡 CONCLUSION:"
echo "   - Si HEAD retourne 200 mais GET retourne 500 → HEAD ne détecte pas l'erreur PHP"
echo "   - Code 206 avec --range est normal (Partial Content)"
echo "   - Utiliser GET complet pour détecter les vraies erreurs 500"
echo ""
echo "✅ Test terminé"