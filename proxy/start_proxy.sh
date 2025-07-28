#!/bin/bash
set -euo pipefail

INFO() { echo -e "[$(date +'%F %T')] [INFO] $*"; }
WARN() { echo -e "[$(date +'%F %T')] [WARN] $*"; }
ERR()  { echo -e "[$(date +'%F %T')] [ERROR] $*" >&2; }

# Pré-requis
for c in docker; do
  command -v "$c" >/dev/null 2>&1 || { ERR "Commande '$c' introuvable. Installe-la puis relance."; exit 1; }
done

PROXY_DIR="/opt/docker-apps/proxy"
COMPOSE_FILE="$PROXY_DIR/docker-compose.yml"
NETWORK="proxy_net"

INFO "Vérification du dossier $PROXY_DIR"
[ -d "$PROXY_DIR" ] || { ERR "Répertoire $PROXY_DIR manquant. Crée-le et place-y docker-compose.yml."; exit 1; }
[ -f "$COMPOSE_FILE" ] || { ERR "Fichier $COMPOSE_FILE introuvable. Copie ton docker-compose.yml du proxy ici."; exit 1; }

INFO "Création du réseau Docker '$NETWORK' (si nécessaire)"
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  docker network create "$NETWORK"
  INFO "Réseau '$NETWORK' créé."
else
  INFO "Réseau '$NETWORK' déjà présent."
fi

INFO "Récupération des images (pull)"
docker compose -f "$COMPOSE_FILE" pull

INFO "Démarrage de NGINX Proxy Manager"
docker compose -f "$COMPOSE_FILE" up -d

INFO "Vérification du statut du conteneur"
docker ps --filter "name=nginx-proxy-manager" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

INFO "Si le statut est 'Up', l'interface doit répondre sur http://<IP_VPS>:81"
INFO "Identifiants par défaut : admin@example.com / changeme"
