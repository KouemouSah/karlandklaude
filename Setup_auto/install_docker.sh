#!/bin/bash

set -e

echo "🔧 Mise à jour du système..."
apt update && apt upgrade -y

echo "📦 Installation des dépendances de base..."
apt install -y sudo curl wget git gnupg ca-certificates lsb-release

echo "🔐 Ajout de la clé GPG de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "🧹 Ajout du dépôt Docker à APT..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "🔄 Mise à jour des paquets APT..."
apt update

echo "🐳 Installation de Docker et plugins..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "✅ Vérification des versions installées..."
docker --version
docker compose version

# Attribution automatique des droits au script (au cas où lancé depuis GitHub)
chmod +x "$0"

echo "🎉 Docker & Docker Compose installés avec succès."