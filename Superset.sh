#!/usr/bin/env bash

# Mode strict pour arrêt en cas d'erreur
set -euo pipefail
trap 'msg_error "Une erreur est survenue à la ligne $LINENO."' ERR

# Fonction pour générer un mot de passe aléatoire
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' </dev/urandom | head -c 16
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

msg_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

msg_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Configuration initiale
APP="Superset"
DEBIAN_VERSION="12"
PYTHON_VERSION="3.11"

# Ressources du conteneur
DISK_SIZE="20" # Go
CPU_CORES="4"
RAM_SIZE="4096" # Mo

# Configurations Superset
msg_info "Mot de passe généré : $(generate_password)"
ADMIN_USER="admin"
if [ -z "${ADMIN_PASSWORD:-}" ]; then
    ADMIN_PASSWORD=$(generate_password)
fi
ADMIN_EMAIL="admin@example.com"
SUPERSET_PORT="8088"

msg_info "Mot de passe généré : $(generate_password)"


# Emplacement du template Debian
TEMPLATE_PATH="/var/lib/vz/template/cache/debian-${DEBIAN_VERSION}-standard_${DEBIAN_VERSION}.0-1_amd64.tar.gz"

# Vérification des prérequis
check_prerequisites() {
    msg_info "Vérification des prérequis..."
    
    # Vérifier si Proxmox est installé
    if [ ! -f "/usr/bin/pct" ]; then
        msg_error "Proxmox VE n'est pas installé."
    fi
    
    # Vérifier l'espace disque disponible
    FREE_SPACE=$(df -BG /var/lib/vz | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_SPACE" -lt "$DISK_SIZE" ]; then
        msg_error "Espace disque insuffisant. Requis: ${DISK_SIZE}G, Disponible: ${FREE_SPACE}G."
    fi
    
    msg_success "Prérequis validés."
}

# Téléchargement du template Debian si nécessaire
download_template() {
    if [ ! -f "$TEMPLATE_PATH" ]; then
        msg_info "Le template Debian $DEBIAN_VERSION n'existe pas. Téléchargement en cours..."
        wget -O "$TEMPLATE_PATH" "https://cdimage.debian.org/cdimage/cloud/bullseye/daily/20231030-2032/debian-${DEBIAN_VERSION}-standard_${DEBIAN_VERSION}.0-1_amd64.tar.gz" || \
            msg_error "Échec du téléchargement du template Debian."
        msg_success "Template Debian téléchargé avec succès."
    else
        msg_info "Le template Debian existe déjà. Aucun téléchargement nécessaire."
    fi
}

# Création du conteneur
create_container() {
    msg_info "Création du conteneur Debian $DEBIAN_VERSION..."
    
    # Trouver le prochain ID disponible
    CONTAINER_ID=$(pvesh get /cluster/nextid)
    
    # Créer le conteneur
    pct create $CONTAINER_ID "$TEMPLATE_PATH" \
        --hostname superset \
        --cores $CPU_CORES \
        --memory $RAM_SIZE \
        --swap 0 \
        --rootfs local-lvm:${DISK_SIZE} \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --onboot 1 \
        --start 1 \
        --unprivileged 1 || msg_error "Échec de la création du conteneur."
    
    # Attendre que le conteneur soit démarré
    sleep 10
    
    # Récupérer l'IP du conteneur
    CONTAINER_IP=$(pct exec $CONTAINER_ID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    msg_success "Conteneur créé avec l'ID: $CONTAINER_ID et l'IP: $CONTAINER_IP."
}

# Installation des dépendances
install_dependencies() {
    msg_info "Installation des dépendances..."
    
    pct exec $CONTAINER_ID -- bash -c "apt update && apt upgrade -y"
    pct exec $CONTAINER_ID -- bash -c "apt install -y \
        build-essential \
        libssl-dev \
        libffi-dev \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev \
        python3-pip \
        libsasl2-dev \
        libldap2-dev \
        libmariadb-dev \
        default-libmysqlclient-dev \
        redis-server \
        nodejs \
        npm \
        git \
        curl \
        wget \
        vim \
        ufw" || msg_error "Échec de l'installation des dépendances."
    
    msg_success "Dépendances installées."
}

# Configuration de l'environnement
setup_environment() {
    msg_info "Configuration de l'environnement..."
    
    # Configurer locales
    pct exec $CONTAINER_ID -- bash -c "apt install -y locales && \
        sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
        locale-gen"
    
    # Créer l'environnement virtuel Python
    pct exec $CONTAINER_ID -- bash -c "python${PYTHON_VERSION} -m venv /opt/superset-venv"
    
    # Configurer Redis
    pct exec $CONTAINER_ID -- bash -c "systemctl enable redis-server && \
        systemctl start redis-server"
    
    msg_success "Environnement configuré."
}

# Installation et configuration de Superset
install_and_configure_superset() {
    msg_info "Installation et configuration de Superset..."
    
    # Installer Superset
    pct exec $CONTAINER_ID -- bash -c "source /opt/superset-venv/bin/activate && \
        pip install --upgrade pip && \
        pip install apache-superset" || msg_error "Échec de l'installation de Superset."
    
    # Initialiser la base de données
    pct exec $CONTAINER_ID -- bash -c "source /opt/superset-venv/bin/activate && \
        superset db upgrade && \
        superset fab create-admin \
            --username ${ADMIN_USER} \
            --firstname Admin \
            --lastname User \
            --email ${ADMIN_EMAIL} \
            --password ${ADMIN_PASSWORD} && \
        superset init" || msg_error "Échec de l'initialisation de Superset."
    
    msg_success "Superset installé et configuré."
}

# Fonction principale
main() {
    check_prerequisites
    download_template
    create_container
    install_dependencies
    setup_environment
    install_and_configure_superset
    msg_success "Installation de Superset terminée."
}

# Exécution du script
main
