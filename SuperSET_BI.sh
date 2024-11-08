#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
    _____                              __   
   / ___/____ ___  ____ _____  ____ _/ /__ 
   \__ \/ __ `__ \/ __ `/ __ \/ __ `/ / _ \
  ___/ / / / / / /_/ / / / / / /_/ / /  __/
 /____/_/ /_/ /_/\__,_/_/ /_/\__, /_/\___/ 
                             /____/         
EOF
}

header_info
APP="Superset"
var_disk="10"
var_cpu="4"
var_ram="4096"
var_os="debian"
var_version="12"
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
  SSH="no"
  VERB="no"
  echo_default
}

function install_superset() {
  header_info
  msg_info "Installing Dependencies"
  apt update
  apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev libsasl2-dev libldap2-dev libssl-dev python3.11-venv
  msg_ok "Dependencies Installed"

  msg_info "Installing Superset"
  python3 -m venv /root/superset-venv
  source /root/superset-venv/bin/activate
  pip install apache-superset
  deactivate
  msg_ok "Superset Installed"

  msg_info "Configuring Superset for Automatic Login and Secure SECRET_KEY"
  # Générer une clé secrète et configurer le fichier de configuration de Superset
  SECRET_KEY=$(openssl rand -base64 42)
  cat <<EOF >/root/superset-venv/lib/python3.11/site-packages/superset_config.py
# Configuration de Superset avec une clé secrète sécurisée et l'authentification désactivée
SECRET_KEY = "$SECRET_KEY"
AUTH_TYPE = 0  # No Auth pour accès automatique
EOF
  msg_ok "Superset Configured with Secure SECRET_KEY"

  msg_info "Setting up Superset Service"
  cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/root/superset-venv
ExecStart=/root/superset-venv/bin/superset run -p 8088 --with-threads --reload --debugger
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable superset
  systemctl start superset
  msg_ok "Superset Service Configured"
}

header_info
start
build_container
description

install_superset

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}:8088${CL} \n"
echo -e "Authentication is disabled for automatic login."
