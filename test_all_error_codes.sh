#!/bin/bash

# Configuration
ROOT="/mnt/www"
PORT="8080"
LOCAL_IP="$(hostname -i | awk '{print $1}')"

echo "=========================================="
echo "🔬 TEST COMPLET DES CODES HTTP"
echo "📍 IP: $LOCAL_IP:$PORT"
echo "=========================================="
echo ""

# Codes à surveiller particulièrement
declare -A error_sites
error_sites[200]=0
error_sites[206]=0
error_sites[301]=0
error_sites[302]=0
error_sites[403]=0
error_sites[404]=0
error_sites[500]=0
error_sites[502]=0
error_sites[503]=0
error_sites[523]=0
error_sites[000]=0

printf "%-35s | %-8s | %-8s | %-8s | %s\n" "SITE" "HEAD" "GET-RANGE" "GET-FULL" "DIAGNOSTIC"
echo "----------------------------------------------------------------------------------------"

cd "$ROOT" || exit 1

# Fonction pour obtenir le diagnostic selon les codes
get_diagnostic() {
    local head=$1
    local range=$2
    local full=$3
    
    # Cas spéciaux
    if [[ "$head" == "200" ]] && [[ "$full" =~ ^[45] ]]; then
        echo "🔴 HEAD MENT!"
    elif [[ "$full" == "000" ]]; then
        echo "⏱️ Timeout"
    elif [[ "$full" == "200" ]] || [[ "$range" == "206" && "$full" == "200" ]]; then
        echo "✅ OK"
    elif [[ "$full" =~ ^3 ]]; then
        echo "↪️ Redirect $full"
    elif [[ "$full" == "403" ]]; then
        echo "🔒 Interdit"
    elif [[ "$full" == "404" ]]; then
        echo "❓ Non trouvé"
    elif [[ "$full" == "500" ]]; then
        echo "💥 Erreur PHP"
    elif [[ "$full" == "502" ]]; then
        echo "🌉 Bad Gateway"
    elif [[ "$full" == "503" ]]; then
        echo "🚧 Maintenance"
    elif [[ "$full" == "523" ]]; then
        echo "☁️ Origin Unreachable"
    else
        echo "⚠️ Code $full"
    fi
}

# Fonction de couleur selon le code
get_color() {
    local code=$1
    if [[ "$code" == "200" ]] || [[ "$code" == "206" ]]; then
        echo "\033[0;32m$code\033[0m"  # Vert
    elif [[ "$code" =~ ^3 ]]; then
        echo "\033[1;33m$code\033[0m"  # Jaune
    elif [[ "$code" =~ ^4 ]]; then
        echo "\033[0;35m$code\033[0m"  # Magenta
    elif [[ "$code" =~ ^5 ]]; then
        echo "\033[0;31m$code\033[0m"  # Rouge
    else
        echo "\033[0;90m$code\033[0m"  # Gris
    fi
}

# Tester 50 sites pour avoir un échantillon varié
count=0
for site in $(ls -d *.* 2>/dev/null | sort -R | head -50); do
    ((count++))
    
    # Test HEAD
    head_code=$(timeout 3 curl -sS -I \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Test GET avec range
    range_code=$(timeout 3 curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --range 0-1024 \
        -X GET \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Test GET complet (limité)
    full_code=$(timeout 3 curl -sS \
        -H "Host: $site" \
        -H "X-Forwarded-Proto: https" \
        --max-time 3 \
        --max-filesize 50000 \
        -o /dev/null \
        -w '%{http_code}' \
        "http://${LOCAL_IP}:${PORT}/" 2>/dev/null || echo "000")
    
    # Compter les codes pour stats
    if [[ -n "${error_sites[$full_code]}" ]]; then
        ((error_sites[$full_code]++))
    else
        ((error_sites[other]++))
    fi
    
    # Diagnostic
    diagnostic=$(get_diagnostic "$head_code" "$range_code" "$full_code")
    
    # Affichage avec couleurs
    head_colored=$(get_color "$head_code")
    range_colored=$(get_color "$range_code")
    full_colored=$(get_color "$full_code")
    
    # Mettre en évidence les cas problématiques
    if [[ "$diagnostic" == "🔴 HEAD MENT!" ]] || [[ "$full_code" =~ ^[45] && "$full_code" != "404" ]]; then
        printf "\033[1;37;41m%-35s\033[0m | %-8b | %-8b | %-8b | %s\n" \
            "${site:0:34}" "$head_colored" "$range_colored" "$full_colored" "$diagnostic"
    else
        printf "%-35s | %-8b | %-8b | %-8b | %s\n" \
            "${site:0:34}" "$head_colored" "$range_colored" "$full_colored" "$diagnostic"
    fi
done

echo "----------------------------------------------------------------------------------------"
echo ""
echo "📊 STATISTIQUES DES CODES HTTP (sur $count sites testés):"
echo ""

# Afficher les stats
for code in 200 206 301 302 403 404 500 502 503 523 000; do
    if [[ ${error_sites[$code]} -gt 0 ]]; then
        percent=$(( error_sites[$code] * 100 / count ))
        colored_code=$(get_color "$code")
        
        # Barre de progression
        bar=""
        bar_length=$(( error_sites[$code] * 30 / count ))
        for ((i=0; i<bar_length; i++)); do bar="${bar}█"; done
        
        printf "  Code %-8b : %3d sites (%3d%%) %s\n" \
            "$colored_code" "${error_sites[$code]}" "$percent" "$bar"
    fi
done

echo ""
echo "🔍 DÉTECTION DES PROBLÈMES:"
echo ""

# Recommandations basées sur les résultats
if [[ ${error_sites[500]} -gt 0 ]]; then
    echo "  ⚠️ ${error_sites[500]} sites avec erreur 500 (PHP/WordPress)"
fi
if [[ ${error_sites[502]} -gt 0 ]]; then
    echo "  ⚠️ ${error_sites[502]} sites avec erreur 502 (Bad Gateway)"
fi
if [[ ${error_sites[503]} -gt 0 ]]; then
    echo "  ⚠️ ${error_sites[503]} sites avec erreur 503 (Maintenance/Surcharge)"
fi
if [[ ${error_sites[523]} -gt 0 ]]; then
    echo "  ⚠️ ${error_sites[523]} sites avec erreur 523 (Cloudflare Origin Unreachable)"
fi
if [[ ${error_sites[404]} -gt 0 ]]; then
    echo "  ℹ️ ${error_sites[404]} sites avec erreur 404 (Page non trouvée)"
fi
if [[ ${error_sites[000]} -gt 0 ]]; then
    echo "  ⏱️ ${error_sites[000]} sites en timeout"
fi

echo ""
echo "💡 RECOMMANDATIONS:"
echo "   • Utiliser GET avec --range pour détecter les vraies erreurs"
echo "   • HEAD peut mentir sur les erreurs 500 (erreurs PHP)"
echo "   • Code 206 avec --range = site OK (Partial Content)"
echo "   • Surveiller particulièrement les codes 500, 502, 503, 523"
echo ""
echo "✅ Test terminé - $(date)"