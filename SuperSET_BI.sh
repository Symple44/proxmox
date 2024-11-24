#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
   _____             __ 
  / ___/____ ___  ____ _____  ____ _/ /__
  \__ \/ __ `/ / / / / __ \/ __ `/ / _ \
 ___/ / /_/ / /_/ / / / / / /_/ / /  __/
/____/\__,_/\__,_/_/ /_/\__, /_/\___/ 
                        /____/          
EOF
}

header_info
APP="Superset"
var_disk="20"
var_cpu="4"
var_ram="4096"
var_os="debian"
var_version="12"
POSTGRES_PASSWORD="Superset2024!"
SUPERSET_USER_PASSWORD="Superset2024!"
ADMIN_PASSWORD="Superset2024!"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="yes"
  VERB="no"
  echo_default
}

function configure_locales() {
  msg_info "Configuration des paramètres régionaux dans le conteneur"

  pct exec $CTID -- bash -c "apt install -y locales"
  pct exec $CTID -- bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
  pct exec $CTID -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
  pct exec $CTID -- bash -c "locale-gen en_US.UTF-8"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration des paramètres régionaux"
    exit 1
  fi

  msg_ok "Paramètres régionaux configurés avec succès"
}

function install_dependencies() {
  msg_info "Installation des dépendances système"
  pct exec $CTID -- bash -c "apt update && apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev curl postgresql"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi
  msg_ok "Dépendances système installées avec succès"
}

function install_postgresql() {
  msg_info "Installation de PostgreSQL"

  # Installer PostgreSQL
  pct exec $CTID -- bash -c "apt update && apt install -y postgresql"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de PostgreSQL"
    exit 1
  fi

  # Démarrer PostgreSQL
  pct exec $CTID -- bash -c "systemctl enable postgresql && systemctl start postgresql"
  if [ $? -ne 0 ]; then
    msg_error "Échec du démarrage de PostgreSQL"
    exit 1
  fi

  # Vérifiez que le service est actif
  pct exec $CTID -- bash -c "systemctl is-active postgresql"
  if [ $? -ne 0 ]; then
    msg_error "PostgreSQL n'est pas actif après l'installation"
    exit 1
  fi

  msg_ok "PostgreSQL installé et démarré avec succès"
}


function locate_pg_hba_conf() {
  msg_info "Recherche du fichier pg_hba.conf"

  # Localiser dynamiquement le fichier pg_hba.conf
  PGB_CONF_PATH=$(pct exec $CTID -- bash -c "find /etc/postgresql -name pg_hba.conf" | tr -d '\r')
  if [ -z "$PGB_CONF_PATH" ]; then
    msg_error "Fichier pg_hba.conf introuvable. Vérifiez l'installation de PostgreSQL."
    exit 1
  fi

  echo "$PGB_CONF_PATH"
}

function configure_pg_authentication() {
  msg_info "Configuration de l'authentification PostgreSQL"

  # Assurez-vous que PostgreSQL est installé
  install_postgresql

  # Localiser le fichier pg_hba.conf
  PGB_CONF_PATH=$(locate_pg_hba_conf)

  # Modifier pg_hba.conf pour activer scram-sha-256
  pct exec $CTID -- bash -c "sed -i 's/local\s*all\s*postgres\s*peer/local all postgres scram-sha-256/' $PGB_CONF_PATH"
  pct exec $CTID -- bash -c "systemctl restart postgresql"

  # Définir le mot de passe PostgreSQL
  pct exec $CTID -- bash -c "psql -U postgres -c \"ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';\""
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de l'authentification PostgreSQL"
    exit 1
  fi

  msg_ok "Authentification PostgreSQL configurée avec succès"
}

function configure_postgresql() {
  msg_info "Configuration de la base de données PostgreSQL pour Superset"

  pct exec $CTID -- bash -c "psql -U postgres -c 'CREATE DATABASE superset;'"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de la base de données Superset"
    exit 1
  fi

  pct exec $CTID -- bash -c "psql -U postgres -c \"CREATE USER superset_user WITH PASSWORD '$SUPERSET_USER_PASSWORD';\""
  pct exec $CTID -- bash -c "psql -U postgres -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de l'utilisateur Superset"
    exit 1
  fi

  msg_ok "Base de données PostgreSQL configurée avec succès"
}

function install_superset() {
  msg_info "Installation d'Apache Superset"

  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset"

  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de Superset"
    exit 1
  fi
  msg_ok "Apache Superset installé avec succès"

  msg_info "Initialisation de Superset"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset db upgrade"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la mise à niveau de la base de données Superset"
    exit 1
  fi

  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@example.com \
    --password $ADMIN_PASSWORD"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de l'utilisateur administrateur Superset"
    exit 1
  fi

  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset init"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'initialisation de Superset"
    exit 1
  fi
  msg_ok "Superset initialisé avec succès"
}

function main() {
  install_dependencies
  configure_locales
  configure_pg_authentication
  configure_postgresql
  install_superset
}

header_info
start
build_container
main
motd_ssh_custom
description

msg_ok "Installation de Superset terminée avec succès!"
echo -e "Accédez à Superset à l'adresse : ${BL}http://${IP}:8088${CL}"
