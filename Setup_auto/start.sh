#!/bin/bash

set -e

echo "🔧 [1/4] Création des dossiers de volumes..."
mkdir -p addons extra-addons postgresql

echo "🌐 [2/4] Vérification du fichier .env..."
if [ ! -f .env ]; then
  echo "❌ Fichier .env manquant. Veuillez créer un fichier .env."
  exit 1
fi

echo "📦 [3/4] Lancement des conteneurs Docker..."
docker compose up -d

if [ $? -eq 0 ]; then
    echo "✅ [4/4] Déploiement réussi : Odoo 17 fonctionne sur le port ${ODOO_PORT}."
    echo "➡️  Accédez à http://<votre-domaine>:${ODOO_PORT}"
else
    echo "❌ Une erreur est survenue pendant le lancement."
fi
