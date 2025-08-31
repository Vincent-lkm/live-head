#!/bin/bash

echo "=========================================="
echo "🔧 SIMULATION D'ERREURS HTTP"
echo "=========================================="
echo ""

SITE=$1
if [[ -z "$SITE" ]]; then
    echo "Usage: $0 <site.com> [code_erreur]"
    echo ""
    echo "Codes disponibles:"
    echo "  403 - Créer un .htaccess qui bloque"
    echo "  404 - Renommer index.php"
    echo "  500 - Créer une erreur PHP"
    echo "  502 - Tuer PHP-FPM"
    echo "  503 - Créer maintenance.flag"
    echo "  301 - Créer une redirection"
    echo "  fix - Réparer le site"
    exit 1
fi

CODE=${2:-500}
SITE_PATH="/mnt/www/$SITE"

if [[ ! -d "$SITE_PATH" ]]; then
    echo "❌ Site non trouvé: $SITE_PATH"
    exit 1
fi

cd "$SITE_PATH"

case $CODE in
    403)
        echo "🔒 Création erreur 403 (Forbidden)..."
        cat > .htaccess << 'EOF'
# Simuler erreur 403
Order Deny,Allow
Deny from all
EOF
        echo "✅ .htaccess créé - Le site retourne maintenant 403"
        ;;
    
    404)
        echo "❓ Création erreur 404 (Not Found)..."
        if [[ -f "index.php" ]]; then
            mv index.php index.php.backup404
            echo "✅ index.php renommé - Le site retourne maintenant 404"
        else
            echo "⚠️ Pas de index.php trouvé"
        fi
        ;;
    
    500)
        echo "💥 Création erreur 500 (Internal Server Error)..."
        cat > index.php << 'EOF'
<?php
// Simulation erreur 500
ini_set('display_errors', 0);
http_response_code(500);

// Créer une erreur PHP fatale
trigger_error("Erreur simulée pour test monitoring", E_USER_ERROR);

// Cette ligne ne sera jamais exécutée
echo "Site OK";
?>
EOF
        echo "✅ index.php modifié - Le site retourne maintenant 500"
        ;;
    
    502)
        echo "🌉 Création erreur 502 (Bad Gateway)..."
        echo "Tentative d'arrêt PHP-FPM (nécessite root)..."
        sudo systemctl stop php7.4-fpm 2>/dev/null || \
        sudo systemctl stop php8.0-fpm 2>/dev/null || \
        sudo systemctl stop php8.1-fpm 2>/dev/null || \
        echo "⚠️ Impossible d'arrêter PHP-FPM (permissions?)"
        
        # Alternative: créer un .htaccess qui proxy vers un port fermé
        cat > .htaccess << 'EOF'
# Simuler erreur 502
RewriteEngine On
RewriteRule ^(.*)$ http://127.0.0.1:9999/$1 [P,L]
EOF
        echo "✅ .htaccess créé avec proxy invalide - Peut causer 502/503"
        ;;
    
    503)
        echo "🚧 Création erreur 503 (Service Unavailable)..."
        cat > .htaccess << 'EOF'
# Simuler erreur 503 - Maintenance
RewriteEngine On
RewriteRule .* - [R=503,L]
ErrorDocument 503 "Maintenance en cours"
EOF
        touch maintenance.flag
        echo "✅ Mode maintenance activé - Le site retourne maintenant 503"
        ;;
    
    301)
        echo "↪️ Création redirection 301..."
        cat > .htaccess << 'EOF'
# Simuler redirection 301
RewriteEngine On
RewriteRule ^(.*)$ https://google.com/$1 [R=301,L]
EOF
        echo "✅ Redirection 301 vers google.com créée"
        ;;
    
    523)
        echo "☁️ Erreur 523 (Origin Unreachable)..."
        echo "Cette erreur est générée par Cloudflare quand le serveur origine ne répond pas."
        echo "Pour la simuler:"
        echo "  1. Bloquer le port 443/80 avec iptables"
        echo "  2. Arrêter Apache: systemctl stop apache2"
        echo "  3. Configurer un firewall qui bloque Cloudflare"
        ;;
    
    timeout)
        echo "⏱️ Création timeout..."
        cat > index.php << 'EOF'
<?php
// Simuler un timeout
sleep(30); // Attendre 30 secondes
echo "Cette page ne devrait jamais se charger";
?>
EOF
        echo "✅ index.php modifié - Le site va timeout"
        ;;
    
    fix|repair)
        echo "🔧 Réparation du site..."
        
        # Supprimer .htaccess problématique
        [[ -f ".htaccess" ]] && rm .htaccess && echo "  - .htaccess supprimé"
        
        # Restaurer index.php
        if [[ -f "index.php.backup404" ]]; then
            mv index.php.backup404 index.php
            echo "  - index.php restauré"
        fi
        
        # Supprimer maintenance flag
        [[ -f "maintenance.flag" ]] && rm maintenance.flag && echo "  - maintenance.flag supprimé"
        
        # Créer un index.php simple si aucun n'existe
        if [[ ! -f "index.php" ]]; then
            cat > index.php << 'EOF'
<?php
// Page de test simple
echo "<!DOCTYPE html><html><head><title>Test</title></head>";
echo "<body><h1>Site OK - " . $_SERVER['HTTP_HOST'] . "</h1>";
echo "<p>Test monitoring: " . date('Y-m-d H:i:s') . "</p>";
echo "</body></html>";
?>
EOF
            echo "  - index.php simple créé"
        fi
        
        echo "✅ Site réparé"
        ;;
    
    *)
        echo "❌ Code non reconnu: $CODE"
        echo "Codes disponibles: 403, 404, 500, 502, 503, 301, timeout, fix"
        exit 1
        ;;
esac

echo ""
echo "📊 Test du site après modification:"
echo "----------------------------------------"

# Tester le site
LOCAL_IP="$(hostname -i | awk '{print $1}')"
echo -n "HEAD: "
curl -sS -I -H "Host: $SITE" -H "X-Forwarded-Proto: https" \
    --max-time 3 -o /dev/null -w '%{http_code}\n' \
    "http://${LOCAL_IP}:8080/" 2>/dev/null || echo "000"

echo -n "GET:  "
curl -sS -H "Host: $SITE" -H "X-Forwarded-Proto: https" \
    --max-time 3 --range 0-1024 -o /dev/null -w '%{http_code}\n' \
    "http://${LOCAL_IP}:8080/" 2>/dev/null || echo "000"

echo ""
echo "✅ Simulation terminée"
echo ""
echo "Pour réparer: $0 $SITE fix"