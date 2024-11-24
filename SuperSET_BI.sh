#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
                         __  
  ________ ________  ___________  ______ _____/  |_ 
 /  ___/  |  \____ \_/ __ \_  __ \/  ___// __ \  __\
 \___ \|  |  /  |_> >  ___/|  | \/\___ \\  ___/|  |  
/____  >____/|   __/ \___  >__|  /____  >\___  >__|  
     \/      |__|        \/          \/     \/       

EOF
}

header_info
APP="Superset"
var_disk="20"
var_cpu="4"
var_ram="4096"
var_os="debian"
var_version="12"
#SUPERSET_USER_PASSWORD="Superset2024!" # Mot de passe pour l'utilisateur superset (non utilisé avec trust)
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
  GATE="" 1 
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
  header_info
  msg_info "Installation des dépendances système"
  # Forcer la mise à jour des paquets
  pct exec $CTID -- bash -c "apt-get update --fix-missing"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la mise à jour du cache APT"
    exit 1
  fi

  # Ajout d'un délai pour permettre aux services réseau de se stabiliser
  sleep 10
    
  pct exec $CTID -- bash -c "apt update && apt upgrade -y"
  # Installer les dépendances
  pct exec $CTID -- bash -c "apt-get install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev curl locales --fix-missing" # Suppression de postgresql
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi

  # Installation des pilotes pour MySQL et SQL Server
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install mysqlclient pyodbc"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des pilotes pour MySQL et SQL Server"
    exit 1
  fi

  msg_ok "Dépendances système installées avec succès"
}

function install_superset() {
  msg_info "Installation de Superset"
  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de Superset"
    exit 1
  fi
  msg_ok "Superset installé avec succès"

  msg_info "Initialisation de Superset"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset db upgrade"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la mise à jour de la base de données Superset"
    exit 1
  fi
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && superset fab create-admin \
    --username admin --firstname Admin --lastname User --email admin@example.com --password $ADMIN_PASSWORD"
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
  # Suppression des fonctions liées à PostgreSQL
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
