#!/bin/bash
# =================================================================================================
# Déploiement automatisé d’Odoo 17 CE avec Docker / Docker Compose
# -------------------------------------------------------------------------------------------------
# Propriétaire : Emac Sah (emacsah@gmail.com) — Data Analyst / DevOps
#
# Architecture cible (VPS LWS Debian 12, multi-apps, reverse-proxy via NGINX Proxy Manager) :
#   /opt/docker-apps/
#   └── karlandklaude.com/
#       ├── .env
#       ├── docker-compose.yml
#       ├── addons/          # modules standard d’Odoo
#       ├── extra-addons/    # modules personnalisés
#       └── postgresql/      # données PostgreSQL (volume)
#
# Ce script :
#   1) vérifie Docker & Compose, et l’exécution en root ;
#   2) crée l’arborescence /opt/docker-apps/karlandklaude.com ;
#   3) génère .env et docker-compose.yml (réseau partagé proxy_net inclus) ;
#   4) lance PostgreSQL + Odoo ;
#   5) initialise la base `karlandklaude` (sans --admin-passwd lors de l’init) ;
#   6) teste l’accès local http://127.0.0.1:8071/web/login.
#
# Utilisation (exécution directe depuis GitHub) :
#   bash <(curl -fsSL https://raw.githubusercontent.com/KouSaT/karlandklaude/setup/Setup_odoo/deploy_odoo17_instance.sh)
#
# Personnalisation par variables d’environnement avant l’appel (facultatif) :
#   PROJECT_SLUG, DB_NAME, ODOO_PORT, ODOO_LONGPOLLING_PORT, POSTGRES_USER, POSTGRES_PASSWORD, etc.
#   Exemple : ODOO_PORT=8091 DB_NAME=ma_base bash <(curl -fsSL .../deploy_odoo17_instance.sh)
# =================================================================================================

set -euo pipefail

# ---------- Mise en forme des messages ----------
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
success(){ echo -e "${GREEN}[SUCCÈS] $1${NC}"; }
error(){   echo -e "${RED}[ERREUR] $1${NC}"; exit 1; }
check_command(){ if eval "$1"; then success "$2"; else error "$3"; fi }

echo "== Début de l'installation automatisée d'Odoo 17 CE =="

# ---------- Sécurité : exécution en root ----------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  error "Ce script doit être exécuté en root (sudo su -)."
fi

# ---------- Variables par défaut (surchargeables) ----------
PROJECT_SLUG="${PROJECT_SLUG:-karlandklaude.com}"   # nom du dossier d’instance
DB_NAME="${DB_NAME:-karlandklaude}"                 # base Odoo
ODOO_VERSION="${ODOO_VERSION:-17}"
POSTGRES_VERSION="${POSTGRES_VERSION:-15}"
ODOO_PORT="${ODOO_PORT:-8071}"                      # HTTP externe
ODOO_LONGPOLLING_PORT="${ODOO_LONGPOLLING_PORT:-8072}"
POSTGRES_USER="${POSTGRES_USER:-christy}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-k@k_25}"
ODOO_MASTER_PASSWORD="${ODOO_MASTER_PASSWORD:-Christy_k@k25}" # utilisé au runtime d’Odoo

BASE="/opt/docker-apps/${PROJECT_SLUG}"
NETWORK="proxy_net"
ODOO_CONTAINER="${ODOO_CONTAINER:-odoo17-karlandklaude}"   # nom conteneur Odoo
DB_CONTAINER="${DB_CONTAINER:-db-karlandklaude}"            # nom conteneur Postgres

# ---------- Pré‑requis : Docker + Compose ----------
check_command "command -v docker >/dev/null" \
  'Docker détecté.' \
  'Docker non présent : installez Docker avant de lancer ce script.'

# Détection Compose (v2 "docker compose" ou v1 "docker-compose")
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  error "Docker Compose introuvable (ni 'docker compose' ni 'docker-compose')."
fi
success "Compose détecté : ${DOCKER_COMPOSE_CMD}"

# ---------- Arborescence ----------
echo "Création de la structure ${BASE}…"
check_command "mkdir -p ${BASE}/{addons,extra-addons,postgresql}" \
  'Répertoires créés.' \
  'Échec de création des répertoires.'

# ---------- Fichier .env ----------
echo "Génération du fichier .env…"
cat > "${BASE}/.env" <<ENV
# === PostgreSQL ===
POSTGRES_DB=${DB_NAME}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_PORT=5432
PGDATA=/var/lib/postgresql/data/pgdata
POSTGRES_VERSION=${POSTGRES_VERSION}

# === Odoo ===
ODOO_VERSION=${ODOO_VERSION}
ODOO_PORT=${ODOO_PORT}
ODOO_LONGPOLLING_PORT=${ODOO_LONGPOLLING_PORT}
ODOO_HTTP_INTERFACE=0.0.0.0
ODOO_DB_FILTER=^${DB_NAME}.*
ODOO_MASTER_PASSWORD=${ODOO_MASTER_PASSWORD}

# === Noms de conteneurs (utilisés par docker-compose et par ce script) ===
ODOO_CONTAINER=${ODOO_CONTAINER}
DB_CONTAINER=${DB_CONTAINER}
ENV
success ".env généré."

# ---------- docker-compose.yml ----------
echo "Génération du docker-compose.yml…"
cat > "${BASE}/docker-compose.yml" <<'YML'
version: '3.8'

services:
  db:
    image: postgres:${POSTGRES_VERSION}
    container_name: ${DB_CONTAINER}
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./postgresql:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 20
    networks:
      - odoo_net

  odoo:
    image: odoo:${ODOO_VERSION}
    container_name: ${ODOO_CONTAINER}
    depends_on:
      - db
    env_file: .env
    ports:
      - "${ODOO_PORT}:8069"           # HTTP externe -> 8069 interne
      - "${ODOO_LONGPOLLING_PORT}:8072"
    volumes:
      - ./addons:/mnt/odoo/addons
      - ./extra-addons:/mnt/extra-addons
    command: >
      bash -c "
        echo '⏳ Attente de PostgreSQL...';
        until pg_isready -h db -p ${POSTGRES_PORT} -U ${POSTGRES_USER}; do sleep 2; done;
        echo '✅ PostgreSQL prêt, lancement d Odoo.';
        /entrypoint.sh odoo
          --db_host=db
          --db_port=${POSTGRES_PORT}
          --db_user=${POSTGRES_USER}
          --db_password=${POSTGRES_PASSWORD}
          --db-filter='${ODOO_DB_FILTER}'
          --proxy-mode
          --http-interface=${ODOO_HTTP_INTERFACE}
          --longpolling-port=${ODOO_LONGPOLLING_PORT}
          --admin-passwd='${ODOO_MASTER_PASSWORD}'
      "
    restart: unless-stopped
    networks:
      - odoo_net
      - proxy_net

networks:
  odoo_net:
  proxy_net:
    external: true
YML
success "docker-compose.yml généré."

# ---------- Réseau partagé (NPM) ----------
echo "Validation du réseau partagé '${NETWORK}'…"
docker network inspect "${NETWORK}" >/dev/null 2>&1 || docker network create "${NETWORK}"
success "Réseau ${NETWORK} prêt."

# ---------- Lancement des conteneurs ----------
cd "${BASE}"
echo "Pull des images…"
check_command "${DOCKER_COMPOSE_CMD} --env-file .env pull" \
  'Images récupérées.' \
  'Échec du pull des images.'
echo "Démarrage des conteneurs…"
check_command "${DOCKER_COMPOSE_CMD} --env-file .env up -d" \
  'Conteneurs démarrés.' \
  'Échec du démarrage des conteneurs.'

# ---------- Initialisation de la base (sans --admin-passwd, à ta demande) ----------
echo "Initialisation de la base '${DB_NAME}' (module base)…"
if docker exec -it "${ODOO_CONTAINER}" odoo \
     --db_host=db --db_port=5432 \
     --db_user="${POSTGRES_USER}" --db_password="${POSTGRES_PASSWORD}" \
     -d "${DB_NAME}" --stop-after-init >/dev/null 2>&1; then
  echo "Base déjà présente, pas d’init nécessaire."
else
  check_command "docker exec -it ${ODOO_CONTAINER} odoo \
    --db_host=db --db_port=5432 \
    --db_user='${POSTGRES_USER}' --db_password='${POSTGRES_PASSWORD}' \
    -d '${DB_NAME}' -i base --without-demo=all --stop-after-init" \
    "Base initialisée." \
    "Échec d'initialisation de la base."
fi

# ---------- Redémarrage & tests ----------
echo "Redémarrage d’Odoo…"
${DOCKER_COMPOSE_CMD} restart odoo >/dev/null 2>&1 || true

echo "Test HTTP local http://127.0.0.1:${ODOO_PORT}/web/login (attente max 60s)…"
for i in {1..30}; do
  if curl -fsS "http://127.0.0.1:${ODOO_PORT}/web/login" >/dev/null 2>&1; then
    success "Odoo répond sur http://<IP_VPS>:${ODOO_PORT}/web/login"
    break
  fi
  sleep 2
done

echo "== Fin de l'installation. Étape suivante : configurer NGINX Proxy Manager =="
echo "- Domain: karlandklaude.com"
echo "- Forward Hostname: ${ODOO_CONTAINER} (réseau proxy_net)"
echo "- Port: 8069 | Custom location /longpolling -> 8072 | Websockets ON"
