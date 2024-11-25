#!/usr/bin/env bash

set -euo pipefail
trap 'msg_error "Une erreur est survenue ààà la ligne $LINENO."' ERR

# Fonction pour générer un mot de passe aléatoire
generate_password() {
    local password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' </dev/urandom | head -c 16)
    if [ -z "$password" ]; then
        msg_error "Échec de la génération du mot de passe."
    fi
    echo "$password"
}

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fonctions d'affichage
msg_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

msg_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Configuration initiale
ADMIN_USER="admin"
ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(generate_password)}
msg_info "Mot de passe administrateur défini : $ADMIN_PASSWORD"

# Exemple d'utilisation
msg_info "Test réussi avec le mot de passe : $ADMIN_PASSWORD"
