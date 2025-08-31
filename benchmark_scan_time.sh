#!/bin/bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"
POD_INFO=$(basename /mnt/www/update/infra*-group* 2>/dev/null | head -n1)
POD_INFO="${POD_INFO:-unknown}"

echo "=========================================="
echo "⏱️  BENCHMARK TEMPS DE SCAN COMPLET"
echo "🏷️  Pod: $POD_INFO"
echo "🌐 IP: $LOCAL_IP:$PORT"
echo "=========================================="
echo ""

cd "$ROOT"

# Compter les sites
total_sites=$(ls -d *.* 2>/dev/null | wc -l)
echo "📊 Nombre de sites à scanner: $total_sites"
echo ""

# ==================== TEST 1: SCAN COMPLET AVEC HEAD ====================
echo "1️⃣ SCAN COMPLET AVEC HEAD..."
echo "----------------------------------------"

start_head=$(date +%s%3N)

for site in $(ls -d *.* 2>/dev/null); do
    curl -sS -I \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --connect-timeout 2 \
        -o /dev/null \
        -w '' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null
done

end_head=$(date +%s%3N)
time_head=$((end_head - start_head))

echo "✅ Terminé en: ${time_head}ms"
echo "   Moyenne par site: $((time_head / total_sites))ms"
echo ""

# ==================== TEST 2: SCAN COMPLET AVEC GET + RANGE ====================
echo "2️⃣ SCAN COMPLET AVEC GET + RANGE..."
echo "----------------------------------------"

start_get=$(date +%s%3N)

for site in $(ls -d *.* 2>/dev/null); do
    curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --connect-timeout 2 \
        --range 0-1024 \
        -X GET \
        -o /dev/null \
        -w '' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null
done

end_get=$(date +%s%3N)
time_get=$((end_get - start_get))

echo "✅ Terminé en: ${time_get}ms"
echo "   Moyenne par site: $((time_get / total_sites))ms"
echo ""

# ==================== TEST 3: SCAN PARALLÈLE AVEC xargs (comme live_head.sh) ====================
echo "3️⃣ SCAN PARALLÈLE (xargs -P 2) AVEC GET..."
echo "----------------------------------------"

# Fonction pour xargs
export -f test_site
export LOCAL_IP PORT

test_site() {
    curl -sS \
        -H "Host: $1" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --connect-timeout 2 \
        --range 0-1024 \
        -X GET \
        -o /dev/null \
        -w '' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null
}

start_parallel=$(date +%s%3N)

ls -d *.* 2>/dev/null | xargs -P 2 -I {} bash -c 'test_site "{}"'

end_parallel=$(date +%s%3N)
time_parallel=$((end_parallel - start_parallel))

echo "✅ Terminé en: ${time_parallel}ms"
echo "   Moyenne par site: $((time_parallel / total_sites))ms"
echo ""

# ==================== RÉSUMÉ ====================
echo "=========================================="
echo "📊 RÉSUMÉ DES TEMPS DE SCAN"
echo "=========================================="
echo ""

echo "🏁 TEMPS TOTAL pour $total_sites sites:"
echo ""
printf "%-30s : %8d ms (%4d ms/site)\n" "HEAD séquentiel" "$time_head" "$((time_head / total_sites))"
printf "%-30s : %8d ms (%4d ms/site)\n" "GET+range séquentiel" "$time_get" "$((time_get / total_sites))"
printf "%-30s : %8d ms (%4d ms/site)\n" "GET+range parallèle (P=2)" "$time_parallel" "$((time_parallel / total_sites))"
echo ""

# Calcul des différences
diff_get_head=$((time_get - time_head))
diff_percent=$(( (diff_get_head * 100) / time_head ))

echo "📈 COMPARAISON:"
echo "  • GET vs HEAD: "
if [[ $diff_get_head -gt 0 ]]; then
    echo "    → GET est ${diff_get_head}ms plus lent (+${diff_percent}%)"
else
    echo "    → GET est ${diff_get_head#-}ms plus rapide (-${diff_percent#-}%)"
fi

echo "  • Parallèle vs Séquentiel:"
speedup=$(( (time_get * 100) / time_parallel ))
echo "    → Parallèle est ${speedup}% plus rapide"
echo ""

echo "💡 RECOMMANDATION:"
if [[ $diff_percent -lt 20 ]]; then
    echo "  ✅ GET+range n'est que ${diff_percent}% plus lent"
    echo "  → Utilisez GET pour détecter les vraies erreurs 500"
else
    echo "  ⚠️ GET+range est ${diff_percent}% plus lent"
    echo "  → Considérez HEAD avec fallback GET sur certains codes"
fi
echo ""
echo "  🚀 Le mode parallèle (xargs -P 2) divise le temps par ~2"
echo "     C'est la méthode utilisée dans live_head.sh"
echo ""
echo "=========================================="