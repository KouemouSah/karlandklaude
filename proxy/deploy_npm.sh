#!/bin/bash
# =================================================================================================
# Déploiement automatisé de NGINX Proxy Manager + configuration d’un Proxy Host Odoo
# -------------------------------------------------------------------------------------------------
# Propriétaire / Auteur : Emac Sah (emacsah@gmail.com) - Data Analyst / DevOps
#
# Structure côté VPS :
#   /opt/docker-apps/
#   └── proxy/
#       ├── docker-compose.yml
#       ├── data/
#       ├── letsencrypt/
#       └── www/.well-known/acme-challenge/   (optionnel, pour diagnostics)
#
# Ce script :
#   1) vérifie root + Docker/Compose,
#   2) synchronise le dossier proxy/ depuis le repo GitHub,
#   3) libère 80/81/443 (arrêt nginx/apache) et ouvre 22,80,81,443,8071 au pare-feu (UFW ou iptables),
#   4) crée le réseau Docker partagé `proxy_net`,
#   5) lance NPM et vérifie l’écoute,
#   6) configure via l’API NPM :
#       - changement des identifiants admin (email + mot de passe),
#       - création du Proxy Host pour karlandklaude.com (+ www),
#       - ajout de la location /longpolling → 8072 (websockets ON),
#       - tentative d’émission du certificat Let’s Encrypt (Force SSL, HTTP/2, HSTS).
#
# Utilisation :
#   bash <(curl -fsSL https://raw.githubusercontent.com/KouSaT/karlandklaude/setup/proxy/deploy_npm.sh)
#
# Variables (surchargeables avant l’appel) :
#   ACME_EMAIL="emacsah@gmail.com"
#   ADMIN_EMAIL="emacsah@gmail.com"
#   ADMIN_PASS="Ngnix@25"
#   ODOO_CONTAINER="odoo17-karlandklaude"
#   DOMAIN_ROOT="karlandklaude.com"
# =================================================================================================

set -euo pipefail

# ----- Mise en forme -----
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok(){ echo -e "${GREEN}[SUCCÈS] $1${NC}"; }
ko(){ echo -e "${RED}[ERREUR] $1${NC}" >&2; }
die(){ ko "$1"; exit 1; }
info(){ echo -e "[INFO] $*"; }

info "== Déploiement NGINX Proxy Manager & configuration Proxy Host =="

# ----- Sécurité : root -----
[ "${EUID:-$(id -u)}" -eq 0 ] || die "Exécutez en root (sudo su -)."

# ----- Paramètres -----
REPO_URL="https://github.com/KouSaT/karlandklaude"
REPO_DIR="/opt/docker-apps/setup-docker"
REPO_BRANCH="setup"
REPO_SUBDIR="proxy"
DEPLOY_DIR="/opt/docker-apps/proxy"
NETWORK="proxy_net"

# Personnalisables
ACME_EMAIL="${ACME_EMAIL:-emacsah@gmail.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-emacsah@gmail.com}"
ADMIN_PASS="${ADMIN_PASS:-Ngnix@25}"
ODOO_CONTAINER="${ODOO_CONTAINER:-odoo17-karlandklaude}"
DOMAIN_ROOT="${DOMAIN_ROOT:-karlandklaude.com}"
DOMAINS_JSON="[\"${DOMAIN_ROOT}\",\"www.${DOMAIN_ROOT}\"]"

# ----- Docker / Compose -----
command -v docker >/dev/null || die "Docker non présent."
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  die "Compose introuvable (ni 'docker compose' ni 'docker-compose')."
fi
ok "Compose détecté : $DC"

# ----- Préparer arborescence -----
mkdir -p /opt/docker-apps || true
ok "Arborescence /opt/docker-apps OK."

# ----- Git : clone / update -----
if [ -d "${REPO_DIR}/.git" ]; then
  info "Mise à jour du dépôt ${REPO_DIR} (branche ${REPO_BRANCH})…"
  git -C "${REPO_DIR}" fetch origin "${REPO_BRANCH}" \
   && git -C "${REPO_DIR}" checkout "${REPO_BRANCH}" \
   && git -C "${REPO_DIR}" reset --hard "origin/${REPO_BRANCH}" \
   || die "Échec mise à jour du dépôt."
else
  info "Clonage du dépôt…"
  git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${REPO_DIR}" \
   || die "Échec clonage du dépôt."
fi
ok "Dépôt prêt."

# ----- Sync proxy/ -> /opt/docker-apps/proxy -----
info "Synchronisation du dossier proxy/…"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "${REPO_DIR}/${REPO_SUBDIR}/" "${DEPLOY_DIR}/" \
   || die "Échec synchronisation (rsync)."
else
  mkdir -p "${DEPLOY_DIR}" && rm -rf "${DEPLOY_DIR:?}/"* \
   && cp -a "${REPO_DIR}/${REPO_SUBDIR}/." "${DEPLOY_DIR}/" \
   || die "Échec synchronisation (cp)."
fi
ok "Fichiers proxy synchronisés."

# ----- docker-compose.yml minimal si absent -----
if [ ! -f "${DEPLOY_DIR}/docker-compose.yml" ]; then
  info "Génération d’un compose minimal pour NPM…"
  cat > "${DEPLOY_DIR}/docker-compose.yml" <<'YML'
version: '3.8'
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - proxy_net
networks:
  proxy_net:
    external: true
YML
  ok "Compose minimal généré."
fi

# ----- Libérer 80/81/443 (nginx/apache) -----
if command -v systemctl >/dev/null 2>&1; then
  for svc in nginx apache2; do
    if systemctl is-active --quiet "$svc"; then
      info "Arrêt + désactivation de $svc pour libérer 80/443…"
      systemctl stop "$svc" || true
      systemctl disable "$svc" || true
      ok "$svc arrêté/désactivé."
    fi
  done
fi

# ----- Pare-feu : ouvrir 22,80,81,443,8071 -----
info "Ouverture des ports au pare-feu (22,80,81,443,8071)…"
open_ports=(22 80 81 443 8071)
if command -v ufw >/dev/null 2>&1; then
  for p in "${open_ports[@]}"; do ufw allow "${p}"/tcp >/dev/null 2>&1 || true; done
  ufw status | grep -qi inactive && yes | ufw enable >/dev/null 2>&1 || true
  ufw logging off >/dev/null 2>&1 || true
  ok "Pare-feu UFW configuré."
else
  ipt_allow(){ iptables -C INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$1" -j ACCEPT; }
  for p in "${open_ports[@]}"; do ipt_allow "$p"; done
  ok "Règles iptables appliquées."
fi

# ----- Réseau partagé -----
docker network inspect "${NETWORK}" >/dev/null 2>&1 || docker network create "${NETWORK}"
ok "Réseau ${NETWORK} prêt."

# ----- Webroot ACME optionnel -----
mkdir -p "${DEPLOY_DIR}/www/.well-known/acme-challenge" || true
ok "Répertoire ACME : ${DEPLOY_DIR}/www/.well-known/acme-challenge"

# ----- Démarrer NPM -----
info "Démarrage NGINX Proxy Manager…"
cd "${DEPLOY_DIR}"
$DC up -d || die "Échec lancement NPM."
ok "Conteneur NPM lancé."

# ----- Vérifier l’écoute -----
sleep 3
ss -ltnp | egrep ':80 |:81 |:443 ' >/dev/null || ko "Attention : ports 80/81/443 non détectés."
$DC ps || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep nginx-proxy-manager || true

# ============================ API NPM : configuration automatisée ===============================
info "Configuration NPM via API… (installation jq si absent)"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y jq curl >/dev/null 2>&1 || true

NPM_BASE="http://127.0.0.1:81"
API="${NPM_BASE}/api"
JWT=""

# Attendre que l’API réponde
for i in {1..30}; do
  if curl -fsS "${NPM_BASE}/" >/dev/null 2>&1; then break; fi; sleep 2
done

# 1) Auth par défaut
login_default(){
  curl -fsS -X POST "${API}/tokens" \
    -H "Content-Type: application/json" \
    -d '{"identity":"admin@example.com","secret":"changeme"}' | jq -r '.token'
}
JWT="$(login_default || true)"
if [ -z "${JWT}" ] || [ "${JWT}" = "null" ]; then
  ko "Impossible de se connecter avec les identifiants par défaut. Continuer sans API."
  echo "➡️  Finissez la configuration via l’UI : http://<IP_VPS>:81"
  exit 0
fi
ok "Connexion API (admin par défaut) OK."

AUTH="Authorization: Bearer ${JWT}"

# 2) Récupérer l’ID de l’utilisateur admin
ADMIN_ID="$(curl -fsS -H "$AUTH" "${API}/users" | jq -r '.[] | select(.email=="admin@example.com") | .id')"
[ -z "${ADMIN_ID}" ] && ADMIN_ID="1"

# 3) Mettre à jour l’email & le mot de passe admin
info "Mise à jour de l’email admin -> ${ADMIN_EMAIL}"
curl -fsS -X PUT "${API}/users/${ADMIN_ID}" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"email\":\"${ADMIN_EMAIL}\",\"name\":\"Admin\",\"nickname\":\"Admin\",\"roles\":[\"admin\"]}" >/dev/null \
  && ok "Email admin mis à jour." || ko "Échec mise à jour email admin."

info "Mise à jour du mot de passe admin…"
curl -fsS -X PUT "${API}/users/${ADMIN_ID}/auth" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"type\":\"password\",\"current_password\":\"changeme\",\"password\":\"${ADMIN_PASS}\"}" >/dev/null \
  && ok "Mot de passe admin mis à jour." || ko "Échec mise à jour mot de passe admin."

# 4) Re-login avec les nouveaux identifiants
JWT="$(curl -fsS -X POST "${API}/tokens" -H "Content-Type: application/json" \
       -d "{\"identity\":\"${ADMIN_EMAIL}\",\"secret\":\"${ADMIN_PASS}\"}" | jq -r '.token' || true)"
if [ -z "${JWT}" ] || [ "${JWT}" = "null" ]; then
  ko "Impossible de se reconnecter avec les nouveaux identifiants."
  echo "➡️  Continuez via l’UI NPM : http://<IP_VPS>:81"
  exit 0
fi
AUTH="Authorization: Bearer ${JWT}"
ok "Connexion API avec nouveaux identifiants OK."

# 5) Créer le Proxy Host (sans SSL d’abord)
info "Création du Proxy Host pour ${DOMAIN_ROOT}…"
PH_PAYLOAD="$(jq -n \
  --argjson domains "${DOMAINS_JSON}" \
  --arg fhost "${ODOO_CONTAINER}" \
  '{domain_names:$domains, forward_scheme:"http", forward_host:$fhost, forward_port:8069,
    access_list_id:0, caching_enabled:false, block_exploits:true, allow_websocket_upgrade:true,
    http2_support:true, hsts_enabled:true, ssl_forced:false, meta:{}}')"

PH_RES="$(curl -fsS -X POST "${API}/nginx/proxy-hosts" -H "$AUTH" -H "Content-Type: application/json" -d "${PH_PAYLOAD}" || true)"
PH_ID="$(echo "$PH_RES" | jq -r '.id // empty')"
if [ -z "${PH_ID}" ]; then
  ko "Échec création Proxy Host (vérifiez que le conteneur ${ODOO_CONTAINER} est joignable sur proxy_net)."
else
  ok "Proxy Host créé (ID=${PH_ID})."
fi

# 6) Ajouter la custom location /longpolling -> 8072 (websocket ON)
if [ -n "${PH_ID}" ]; then
  info "Ajout de la custom location /longpolling…"
  LOC_PAYLOAD='{"path":"/longpolling","forward_scheme":"http","forward_host":"'${ODOO_CONTAINER}'","forward_port":8072,"block_exploits":true,"allow_websocket_upgrade":true,"caching_enabled":false}'
  curl -fsS -X POST "${API}/nginx/proxy-hosts/${PH_ID}/locations" -H "$AUTH" -H "Content-Type: application/json" -d "${LOC_PAYLOAD}" >/dev/null \
    && ok "Location /longpolling ajoutée." \
    || ko "Échec ajout location /longpolling."
fi

# 7) Tentative d’obtention du certificat Let’s Encrypt
#    Conditions : DNS A -> IP VPS et port 80 ouvert & joignable
info "Tentative d’émission du certificat Let’s Encrypt…"
LE_PAYLOAD="$(jq -n \
  --argjson domains "${DOMAINS_JSON}" \
  --arg email "${ACME_EMAIL}" \
  '{provider:"letsencrypt", nice_name:null, domain_names:$domains, metadata:{}, \
    key: null, cert: null, \
    renew_days: 30, auto_renew: true, \
    letsencrypt_agree: true, letsencrypt_email:$email, ssl_forced:true, hsts_enabled:true, http2_support:true}')"

CERT_RES="$(curl -fsS -X POST "${API}/nginx/certificates" -H "$AUTH" -H "Content-Type: application/json" -d "${LE_PAYLOAD}" || true)"
CERT_ID="$(echo "$CERT_RES" | jq -r '.id // empty')"

if [ -n "${CERT_ID}" ] && [ -n "${PH_ID}" ]; then
  # lier le certificat au proxy host et forcer SSL
  PH_UPDATE="$(jq -n --argjson cid "${CERT_ID}" '{"certificate_id":$cid,"ssl_forced":true,"http2_support":true,"hsts_enabled":true}')"
  curl -fsS -X PUT "${API}/nginx/proxy-hosts/${PH_ID}" -H "$AUTH" -H "Content-Type: application/json" -d "${PH_UPDATE}" >/dev/null \
    && ok "Certificat LE appliqué au Proxy Host (SSL forcé)." \
    || ko "Certificat obtenu mais non appliqué au Proxy Host."
else
  ko "Échec émission certificat (DNS/port 80 ?). Vous pourrez le demander via l’UI NPM."
fi

IPV4="$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9.]+$/){print $i; exit}}')"
echo
echo "== Terminé =="
echo "UI NPM           : http://${IPV4:-<IP_VPS>}:81  (login: ${ADMIN_EMAIL})"
echo "Proxy Host       : http://${DOMAIN_ROOT}  (SSL appliqué si succès Let’s Encrypt)"
echo "Cible Odoo       : ${ODOO_CONTAINER}:8069  (/longpolling → 8072)"
echo "En cas d’échec SSL : vérifier DNS (A → IP VPS) + port 80, puis relancer l’émission via l’UI."
