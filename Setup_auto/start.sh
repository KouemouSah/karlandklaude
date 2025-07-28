#!/bin/bash
set -euo pipefail

INFO(){ echo -e "[$(date +'%F %T')] [INFO] $*"; }
ERR(){  echo -e "[$(date +'%F %T')] [ERROR] $*" >&2; }

NETWORK="proxy_net"

# 0) Pré-requis
command -v docker >/dev/null 2>&1 || { ERR "Docker introuvable."; exit 1; }

# 1) Contrôles de base
[ -f ".env" ] || { ERR "Fichier .env manquant."; exit 1; }
[ -f "docker-compose.yml" ] || { ERR "docker-compose.yml manquant."; exit 1; }

# 2) Volumes
INFO "Création des dossiers de volumes (addons, extra-addons, postgresql)"
mkdir -p addons extra-addons postgresql

# 3) Réseau partagé pour le proxy (idempotent)
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  INFO "Création du réseau Docker '$NETWORK'"
  docker network create "$NETWORK"
else
  INFO "Réseau '$NETWORK' déjà présent"
fi

# 4) Récupération des images
INFO "docker compose pull (avec .env)"
docker compose --env-file .env pull

# 5) Démarrage
INFO "docker compose up -d"
docker compose --env-file .env up -d

# 6) État
INFO "État des services :"
docker compose ps

# 7) Test HTTP local (attente jusqu'à 2 min)
ODOO_PORT_VAL="$(grep '^ODOO_PORT=' .env | cut -d'=' -f2)"
INFO "Test HTTP : http://127.0.0.1:${ODOO_PORT_VAL}/web/login"
ATTEMPTS=60
until curl -fsS "http://127.0.0.1:${ODOO_PORT_VAL}/web/login" >/dev/null 2>&1 || [ $ATTEMPTS -eq 0 ]; do
  sleep 2
  ATTEMPTS=$((ATTEMPTS-1))
done

if [ $ATTEMPTS -eq 0 ]; then
  ERR "Odoo ne répond pas encore sur ${ODOO_PORT_VAL}. Consulte les logs ci-dessous."
  docker logs --tail=120 odoo17-karlandklaude || true
  exit 1
fi

INFO "✅ Odoo répond localement : http://127.0.0.1:${ODOO_PORT_VAL}"
INFO "Tu peux aussi tester : http://<IP_DU_SERVEUR>:${ODOO_PORT_VAL}"
