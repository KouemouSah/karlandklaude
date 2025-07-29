#!/bin/bash
set -euo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
success(){ echo -e "${GREEN}[SUCCÈS] $1${NC}"; }
error(){   echo -e "${RED}[ERREUR] $1${NC}" >&2; exit 1; }
step(){    echo -e "\n==== $* ===="; }

step "Arrêt & suppression des stacks docker-compose (si présentes)"
cd /opt/docker-apps/odoo17-karlandklaude.com 2>/dev/null && docker compose down -v || true
cd /opt/docker-apps/setup-docker/proxy        2>/dev/null && docker compose down -v || true
success "Stacks arrêtées"

step "Suppression des conteneurs résiduels"
docker rm -f nginx-proxy-manager odoo17-karlandklaude db-karlandklaude 2>/dev/null || true
success "Conteneurs résiduels supprimés"

step "Suppression du réseau partagé proxy_net (si présent)"
docker network rm proxy_net 2>/dev/null || true
success "Réseau proxy_net supprimé (si existait)"

step "Suppression des dossiers de données Odoo & NPM (le dépôt Git est conservé)"
rm -rf /opt/docker-apps/odoo17-karlandklaude.com
rm -rf /opt/docker-apps/setup-docker/proxy/data /opt/docker-apps/setup-docker/proxy/letsencrypt
success "Données locales supprimées"

step "Nettoyage Docker (images/volumes orphelins)"
docker system prune -af --volumes >/dev/null 2>&1 || true
success "Prune terminé"

echo -e "\n${GREEN}✅ Remise à zéro terminée. Le dépôt /opt/docker-apps/setup-docker est conservé.${NC}"
