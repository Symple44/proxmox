#!/usr/bin/env bash

# Variables globales
APP="Superset"
DISK_SIZE="20"
CPU="4"
RAM="4096"
OS="debian"
OS_VERSION="12"
CTID=$(pvesh get /cluster/nextid)
BRIDGE="vmbr0"
POSTGRES_PASSWORD="Superset2024!"
SUPERSET_USER_PASSWORD="Superset2024!"
ADMIN_PASSWORD="Superset2024!"
IP="dhcp"
SETTINGS_FILE="/etc/postgresql/*/main/pg_hba.conf"

# Fonctions utilitaires
function msg_info() {
  echo -e "\e[36m[INFO]\e[0m $1"
}

function msg_ok() {
  echo -e "\e[32m[OK]\e[0m $1"
}

function msg_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

# Création du conteneur
function create_container() {
  msg_info "Création du conteneur LXC pour $APP"
  pct create $CTID local:vztmpl/${OS}-${OS_VERSION}-standard_12.0-1_amd64.tar.zst \
    -features "nesting=1" \
    -hostname $APP \
    -storage local-lvm \
    -net0 name=eth0,bridge=$BRIDGE,ip=$IP \
    -cores $CPU \
    -memory $RAM \
    -rootfs ${DISK_SIZE}G
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création du conteneur"
    exit 1
  fi
  msg_ok "Conteneur $APP créé avec succès"
}

# Démarrage du conteneur
function start_container() {
  msg_info "Démarrage du conteneur $APP"
  pct start $CTID
  if [ $? -ne 0 ]; then
    msg_error "Échec du démarrage du conteneur"
    exit 1
  fi
  msg_ok "Conteneur $APP démarré avec succès"
}

# Configuration des locales
function configure_locales() {
  msg_info "Configuration des locales dans le conteneur"
  pct exec $CTID -- bash -c "apt update && apt install -y locales"
  pct exec $CTID -- bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
  pct exec $CTID -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
  pct exec $CTID -- bash -c "locale-gen en_US.UTF-8"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration des locales"
    exit 1
  fi
  msg_ok "Locales configurées avec succès"
}

# Installation des dépendances
function install_dependencies() {
  msg_info "Installation des dépendances dans le conteneur"
  pct exec $CTID -- bash -c "apt update && apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev curl postgresql locales --fix-missing"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi
  msg_ok "Dépendances installées avec succès"
}

# Configuration de PostgreSQL
function configure_postgresql() {
  msg_info "Configuration de PostgreSQL"
  # Modification du fichier pg_hba.conf pour activer l'authentification scram-sha-256
  pct exec $CTID -- bash -c "sed -i 's/local\s*all\s*postgres\s*peer/local all postgres scram-sha-256/' $SETTINGS_FILE"
  pct exec $CTID -- bash -c "systemctl restart postgresql"

  # Définir un mot de passe pour l'utilisateur postgres
  pct exec $CTID -- bash -c "PGPASSWORD='' psql -U postgres -c \"ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';\""
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de l'utilisateur postgres"
    exit 1
  fi

  # Créer la base de données et un utilisateur pour Superset
  pct exec $CTID -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c 'CREATE DATABASE superset;'"
  pct exec $CTID -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c \"CREATE USER superset_user WITH PASSWORD '$SUPERSET_USER_PASSWORD';\""
  pct exec $CTID -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de la base de données Superset"
    exit 1
  fi
  msg_ok "PostgreSQL configuré avec succès"
}

# Installation de Superset
function install_superset() {
  msg_info "Installation de Superset"
  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de Superset"
    exit 1
  fi
  msg_ok "Superset installé avec succès"

  # Initialisation de Superset
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset db upgrade"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset fab create-admin \
    --username admin --firstname Admin --lastname User --email admin@example.com --password $ADMIN_PASSWORD"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset init"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'initialisation de Superset"
    exit 1
  fi
  msg_ok "Superset initialisé avec succès"
}

# Point d'entrée principal
function main() {
  create_container
  start_container
  configure_locales
  install_dependencies
  configure_postgresql
  install_superset
}

main
msg_ok "Installation de Superset terminée avec succès !"
echo -e "Accédez à Superset à l'adresse : http://${IP}:8088"
