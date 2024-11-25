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
ADMIN_PASSWORD="Superset2024!" # Mot de passe administrateur
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
  header_info
  msg_info "Installation des dépendances système"
  
  # Mise à jour et installation des paquets requis
  pct exec $CTID -- bash -c "apt-get update --fix-missing && apt-get upgrade -y"
  pct exec $CTID -- bash -c "apt-get install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev curl locales"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi
  msg_ok "Dépendances système installées avec succès"
}

function install_superset() {
  msg_info "Installation de Superset"
  
  # Création de l'environnement Python virtuel
  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de Superset"
    exit 1
  fi
  msg_ok "Superset installé avec succès"

  # Création du fichier de configuration personnalisé
  pct exec $CTID -- bash -c "cat > /opt/superset-venv/superset_config.py << EOF
import os
from datetime import timedelta

SECRET_KEY = 'thisISaSECRET_1234'
SQLALCHEMY_DATABASE_URI = 'sqlite:////opt/superset-venv/superset.db'
SQLALCHEMY_TRACK_MODIFICATIONS = False
CACHE_CONFIG = {
    'CACHE_TYPE': 'SimpleCache',
    'CACHE_DEFAULT_TIMEOUT': 300
}
EOF"

  # Initialisation de Superset avec FLASK_APP défini
  msg_info "Initialisation de Superset"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/opt/superset-venv/superset_config.py && superset db upgrade"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la mise à jour de la base de données Superset"
    exit 1
  fi

  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/opt/superset-venv/superset_config.py && superset fab create-admin \
    --username admin --firstname Admin --lastname User --email admin@example.com --password $ADMIN_PASSWORD"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de l'utilisateur administrateur Superset"
    exit 1
  fi

  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/opt/superset-venv/superset_config.py && superset init"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'initialisation de Superset"
    exit 1
  fi
  msg_ok "Superset initialisé avec succès"
}

function configure_firewall() {
  msg_info "Configuration du pare-feu et autorisation du port 8088"
  pct exec $CTID -- bash -c "apt install -y ufw && ufw allow 8088 && ufw --force enable"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration du pare-feu"
    exit 1
  fi
  msg_ok "Pare-feu configuré avec succès"
}

function motd_ssh_custom() {
  msg_info "Customizing MOTD and SSH access"
  # Customize MOTD with Superset specific message
  pct exec $CTID -- bash -c "echo 'Welcome to your Superset LXC container!' > /etc/motd"
  
  # Set up auto-login for root on tty1
  pct exec $CTID -- mkdir -p /etc/systemd/system/container-getty@1.service.d
  pct exec $CTID -- bash -c "cat <<EOF >/etc/systemd/system/container-getty@1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \\$TERM
EOF"

  # Reload systemd and restart getty service to apply auto-login
  pct exec $CTID -- systemctl daemon-reload
  pct exec $CTID -- systemctl restart container-getty@1.service
  msg_ok "MOTD and SSH access customized"
}


function main() {
  install_dependencies
  configure_locales
  install_superset
  configure_firewall
}

header_info
start
build_container
main
motd_ssh_custom
description

msg_ok "Installation de Superset terminée avec succès!"
echo -e "Accédez à Superset à l'adresse : ${BL}http://${IP}:8088${CL}"
