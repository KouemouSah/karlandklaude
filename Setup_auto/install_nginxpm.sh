#!/bin/bash

set -e

echo "🔧 [1/5] Création du dossier NGINX Proxy Manager..."

INSTALL_DIR="/opt/docker-apps/proxy"

if [ -d "$INSTALL_DIR" ]; then
  echo "✅ Le dossier $INSTALL_DIR existe déjà."
else
  mkdir -p "$INSTALL_DIR"
  echo "📁 Dossier $INSTALL_DIR créé."
fi

cd "$INSTALL_DIR" || { echo "❌ Erreur : impossible d'accéder à $INSTALL_DIR"; exit 1; }

echo "📝 [2/5] Génération du fichier docker-compose.yml..."

cat <<EOF > docker-compose.yml
version: '3'

services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: always
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    environment:
      DB_MYSQL_HOST: db
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: npm
      DB_MYSQL_PASSWORD: npm
      DB_MYSQL_NAME: npm
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    depends_on:
      - db

  db:
    image: mariadb:10.5
    container_name: nginxpm-db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: npm
      MYSQL_USER: npm
      MYSQL_PASSWORD: npm
    volumes:
      - ./data/mysql:/var/lib/mysql
EOF

echo "📦 [3/5] Fichier docker-compose.yml créé avec succès."

echo "🚀 [4/5] Lancement de NGINX Proxy Manager..."
docker compose up -d || { echo "❌ Échec lors du lancement de docker compose"; exit 1; }

echo "✅ NGINX Proxy Manager est lancé."

echo "🔐 [5/5] Accès Web : http://<IP_DU_SERVEUR>:81"
echo "Identifiants par défaut :"
echo "  📧 Email : admin@example.com"
echo "  🔑 Mot de passe : changeme"
