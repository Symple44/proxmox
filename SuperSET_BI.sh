#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
    _____                              __   
   / ___/____ ___  ____ _____  ____ _/ /__ 
   \__ \/ __ `__ \/ __ `/ __ \/ __ `/ / _ \
  ___/ / / / / / / /_/ / / / / /_/ / /  __/
 /____/_/ /_/ /_/\__,_/_/ /_/\__, /_/\___/ 
                             /____/         
EOF
}
header_info
echo -e "Loading..."
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
  apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev libsasl2-dev libldap2-dev libssl-dev
  msg_ok "Dependencies Installed"

  msg_info "Installing Superset"
  python3 -m venv /root/superset-venv
  source /root/superset-venv/bin/activate
  pip install apache-superset
  deactivate
  msg_ok "Superset Installed"

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

function create_admin_user() {
  msg_info "Creating Admin User for Superset"
  source /root/superset-venv/bin/activate
  superset fab create-admin \
      --username admin \
      --firstname Superset \
      --lastname Admin \
      --email admin@example.com \
      --password admin
  deactivate
  msg_ok "Admin User Created (username: admin, password: admin)"
}

start
build_container
description

# Appel de la fonction pour installer Superset et créer un utilisateur administrateur
install_superset
create_admin_user

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}:8088${CL} \n"
echo -e "Login with username: admin and password: admin"
