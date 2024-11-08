#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
    _                                           
   | |                                     _    
    \ \  _   _ ____   ____  ____ ___  ____| |_  
     \ \| | | |  _ \ / _  )/ ___)___)/ _  )  _) 
 _____) ) |_| | | | ( (/ /| |  |___ ( (/ /| |__ 
(______/ \____| ||_/ \____)_|  (___/ \____)\___)
              |_|                               
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
  python3 -m venv superset-venv
  source superset-venv/bin/activate
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

function update_script() {
  header_info
  if [[ ! -d /root/superset-venv ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
  msg_info "Updating $APP (Patience)"
  source /root/superset-venv/bin/activate
  pip install --upgrade apache-superset
  deactivate
  systemctl restart superset
  msg_ok "Updated $APP"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}:8088${CL} \n"
