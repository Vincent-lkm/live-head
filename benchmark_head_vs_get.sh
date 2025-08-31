#!/usr/bin/env bash
set -euo pipefail

# Configuration
ROOT="/mnt/www"
PORT="${PORT:-8080}"
LOCAL_IP="$(hostname -i | awk '{print $1}')"
POD_INFO=$(basename /mnt/www/update/infra*-group* 2>/dev/null | head -n1)
POD_INFO="${POD_INFO:-unknown}"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables pour les statistiques
total_sites=0
head_correct=0
head_incorrect=0
get_correct=0
total_time_head=0
total_time_get=0
differences=()

echo "=========================================="
echo "🔬 BENCHMARK HEAD vs GET - $(date)"
echo "📍 Pod: $POD_INFO"
echo "🌐 IP: $LOCAL_IP:$PORT"
echo "=========================================="
echo ""

# Fonction test avec HEAD
test_with_head() {
    local site="$1"
    local url="http://${LOCAL_IP}:${PORT}/"
    
    local start=$(date +%s%N)
    read -r code time_total <<<$(curl -sS -I \
        -H "Host: ${site}" \
        -H "X-Forwarded-Proto: https" \
        --max-time 10 --connect-timeout 3 \
        -o /dev/null \
        -w '%{http_code} %{time_total}' \
        "$url" 2>/dev/null || echo "000 0")
    local end=$(date +%s%N)
    
    local duration=$(( (end - start) / 1000000 )) # en ms
    echo "$code $duration"
}

# Fonction test avec GET + range
test_with_get() {
    local site="$1"
    local url="http://${LOCAL_IP}:${PORT}/"
    
    local start=$(date +%s%N)
    read -r code time_total <<<$(curl -sS \
        -H "Host: ${site}" \
        -H "X-Forwarded-Proto: https" \
        --max-time 10 --connect-timeout 3 \
        --range 0-1024 \
        -X GET \
        -o /dev/null \
        -w '%{http_code} %{time_total}' \
        "$url" 2>/dev/null || echo "000 0")
    local end=$(date +%s%N)
    
    local duration=$(( (end - start) / 1000000 )) # en ms
    echo "$code $duration"
}

# Tableau récapitulatif header
printf "%-40s | %-12s | %-12s | %-10s | %s\n" \
    "SITE" "HEAD" "GET" "MATCH?" "DIFF(ms)"
echo "--------------------------------------------------------------------------------"

# Scanner tous les sites
cd "$ROOT"
for d in *; do
    # Ignorer les non-répertoires et certains dossiers
    [[ ! -d "$d" ]] && continue
    [[ "$d" =~ ^(update|backups|readyz|new|lost\+found)$ ]] && continue
    
    # Limiter pour le test (optionnel)
    if [[ $total_sites -ge 50 ]]; then
        echo ""
        echo "⚠️  Limité à 50 sites pour le benchmark"
        break
    fi
    
    ((total_sites++))
    
    # Test avec HEAD
    read -r head_code head_time <<<$(test_with_head "$d")
    total_time_head=$((total_time_head + head_time))
    
    # Test avec GET
    read -r get_code get_time <<<$(test_with_get "$d")
    total_time_get=$((total_time_get + get_time))
    
    # Comparer les résultats
    if [[ "$head_code" == "$get_code" ]]; then
        match_status="${GREEN}✓ MATCH${NC}"
        ((head_correct++))
        ((get_correct++))
    else
        match_status="${RED}✗ DIFF${NC}"
        ((head_incorrect++))
        differences+=("$d: HEAD=$head_code GET=$get_code")
    fi
    
    # Différence de temps
    time_diff=$((get_time - head_time))
    
    # Affichage avec couleurs selon le status
    if [[ "$get_code" == "200" ]]; then
        status_color="${GREEN}"
    elif [[ "$get_code" =~ ^3 ]]; then
        status_color="${YELLOW}"
    elif [[ "$get_code" =~ ^5 ]]; then
        status_color="${RED}"
    else
        status_color="${BLUE}"
    fi
    
    printf "%-40s | ${status_color}%-12s${NC} | ${status_color}%-12s${NC} | %-10b | %+6d ms\n" \
        "${d:0:39}" \
        "[$head_code] ${head_time}ms" \
        "[$get_code] ${get_time}ms" \
        "$match_status" \
        "$time_diff"
done

echo "--------------------------------------------------------------------------------"
echo ""
echo "📊 RÉSULTATS DU BENCHMARK"
echo "=========================================="
echo ""

# Statistiques
echo "📈 Statistiques générales:"
echo "   - Sites testés: $total_sites"
echo "   - Codes identiques: $head_correct/$total_sites ($(( head_correct * 100 / total_sites ))%)"
echo "   - Codes différents: $head_incorrect/$total_sites ($(( head_incorrect * 100 / total_sites ))%)"
echo ""

# Temps moyens
if [[ $total_sites -gt 0 ]]; then
    avg_head=$((total_time_head / total_sites))
    avg_get=$((total_time_get / total_sites))
    echo "⏱️  Performance:"
    echo "   - Temps moyen HEAD: ${avg_head}ms"
    echo "   - Temps moyen GET: ${avg_get}ms"
    echo "   - Différence: $((avg_get - avg_head))ms (+$(( (avg_get - avg_head) * 100 / avg_head ))%)"
    echo ""
fi

# Afficher les différences s'il y en a
if [[ ${#differences[@]} -gt 0 ]]; then
    echo "⚠️  Sites avec codes différents:"
    for diff in "${differences[@]}"; do
        echo "   - $diff"
    done
    echo ""
fi

# Recommandation
echo "💡 RECOMMANDATION:"
if [[ $head_incorrect -eq 0 ]]; then
    echo "   ✅ HEAD est fiable et $(( (avg_get - avg_head) * 100 / avg_head ))% plus rapide"
    echo "   → Utiliser HEAD avec fallback GET sur erreur"
elif [[ $head_incorrect -lt $(( total_sites / 10 )) ]]; then
    echo "   ⚠️  HEAD a ${head_incorrect} erreurs ($(( head_incorrect * 100 / total_sites ))%)"
    echo "   → Utiliser HEAD avec fallback GET étendu"
else
    echo "   ❌ HEAD n'est pas fiable ($(( head_incorrect * 100 / total_sites ))% d'erreurs)"
    echo "   → Utiliser GET directement malgré le surcoût de ${avg_get}ms"
fi

echo ""
echo "=========================================="
echo "✅ Benchmark terminé - $(date)"
echo "==========================================">