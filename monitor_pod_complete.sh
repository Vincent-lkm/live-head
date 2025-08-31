#!/bin/bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"
POD_INFO=$(basename /mnt/www/update/infra*-group* 2>/dev/null | head -n1)
POD_INFO="${POD_INFO:-unknown}"

# Stats
total_sites=0
ok_200=0
ok_206=0
error_3xx=0
error_4xx=0
error_5xx=0
error_000=0
total_time_head=0
total_time_get=0
head_lies=0

echo "=========================================="
echo "📊 MONITORING COMPLET DU POD"
echo "🏷️  Pod: $POD_INFO"
echo "🌐 IP: $LOCAL_IP:$PORT"
echo "⏰ Début: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

# Fonction test HEAD
test_head() {
    local site="$1"
    curl -sS -I \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --connect-timeout 2 \
        -o /dev/null \
        -w '%{http_code} %{time_total}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000 0"
}

# Fonction test GET avec range (recommandé)
test_get_range() {
    local site="$1"
    curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --connect-timeout 2 \
        --range 0-1024 \
        -X GET \
        -o /dev/null \
        -w '%{http_code} %{time_total}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000 0"
}

echo "Scan en cours..."
echo ""

# Scanner tous les sites
cd "$ROOT"
start_time=$(date +%s)

for site in $(ls -d *.* 2>/dev/null); do
    ((total_sites++))
    
    # Test HEAD
    read -r head_code head_time <<<$(test_head "$site")
    head_ms=$(awk -v t="$head_time" 'BEGIN{printf("%d", t*1000)}')
    total_time_head=$((total_time_head + head_ms))
    
    # Test GET avec range
    read -r get_code get_time <<<$(test_get_range "$site")
    get_ms=$(awk -v t="$get_time" 'BEGIN{printf("%d", t*1000)}')
    total_time_get=$((total_time_get + get_ms))
    
    # Normaliser le code (206 = 200 pour les stats)
    display_code=$get_code
    if [[ "$get_code" == "206" ]]; then
        ((ok_206++))
        get_code="200"  # Pour l'envoi à l'API
    fi
    
    # Compter les codes
    if [[ "$get_code" == "200" ]]; then
        ((ok_200++))
    elif [[ "$get_code" =~ ^3 ]]; then
        ((error_3xx++))
    elif [[ "$get_code" =~ ^4 ]]; then
        ((error_4xx++))
    elif [[ "$get_code" =~ ^5 ]]; then
        ((error_5xx++))
    elif [[ "$get_code" == "000" ]]; then
        ((error_000++))
    fi
    
    # Détecter si HEAD ment
    if [[ "$head_code" == "200" ]] && [[ "$get_code" =~ ^5 ]]; then
        ((head_lies++))
        echo "  ⚠️ HEAD MENT: $site (HEAD=$head_code, GET=$display_code)"
    fi
    
    # Afficher progression tous les 100 sites
    if [[ $((total_sites % 100)) -eq 0 ]]; then
        echo "  📍 $total_sites sites scannés..."
    fi
done

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "=========================================="
echo "📈 RÉSULTATS DU MONITORING"
echo "=========================================="
echo ""

# Stats générales
echo "📊 STATISTIQUES GLOBALES:"
echo "  • Sites scannés: $total_sites"
echo "  • Durée du scan: ${duration}s"
echo "  • Pod: $POD_INFO"
echo ""

# Distribution des codes
echo "🎯 CODES HTTP (méthode GET recommandée):"
total_ok=$((ok_200 + ok_206))
echo "  ✅ OK (200/206): $total_ok sites ($(( total_ok * 100 / total_sites ))%)"
[[ $error_3xx -gt 0 ]] && echo "  ↪️ Redirections (3xx): $error_3xx sites ($(( error_3xx * 100 / total_sites ))%)"
[[ $error_4xx -gt 0 ]] && echo "  ⚠️ Erreurs client (4xx): $error_4xx sites ($(( error_4xx * 100 / total_sites ))%)"
[[ $error_5xx -gt 0 ]] && echo "  🔴 Erreurs serveur (5xx): $error_5xx sites ($(( error_5xx * 100 / total_sites ))%)"
[[ $error_000 -gt 0 ]] && echo "  ⏱️ Timeouts (000): $error_000 sites ($(( error_000 * 100 / total_sites ))%)"
echo ""

# Performance
if [[ $total_sites -gt 0 ]]; then
    avg_head=$((total_time_head / total_sites))
    avg_get=$((total_time_get / total_sites))
    echo "⚡ PERFORMANCE:"
    echo "  • Temps moyen HEAD: ${avg_head}ms"
    echo "  • Temps moyen GET: ${avg_get}ms"
    echo "  • Différence: $((avg_get - avg_head))ms"
    echo "  • Sites/seconde: $(( total_sites / duration ))"
    echo ""
fi

# Détection des mensonges HEAD
if [[ $head_lies -gt 0 ]]; then
    echo "🚨 PROBLÈME DÉTECTÉ:"
    echo "  HEAD a menti sur $head_lies sites ($(( head_lies * 100 / total_sites ))%)"
    echo "  → Ces sites retournent 200 en HEAD mais une erreur en GET"
    echo ""
fi

# Recommandation finale
echo "💡 RECOMMANDATION:"
if [[ $head_lies -eq 0 ]]; then
    echo "  ✅ HEAD est fiable sur ce pod"
    echo "  → Peut utiliser HEAD avec fallback GET pour optimiser"
else
    echo "  ⚠️ HEAD n'est PAS fiable sur ce pod ($head_lies mensonges)"
    echo "  → UTILISER GET avec --range pour un monitoring précis"
fi

echo ""
echo "📋 RÉSUMÉ POUR ENVOI API:"
echo "  • Total sites OK: $total_ok"
echo "  • Total erreurs: $((error_3xx + error_4xx + error_5xx + error_000))"
echo "  • Temps moyen: ${avg_get}ms"
echo "  • Fiabilité HEAD: $(( (total_sites - head_lies) * 100 / total_sites ))%"
echo ""
echo "=========================================="
echo "✅ Monitoring terminé: $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================">