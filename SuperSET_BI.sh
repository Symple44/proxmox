#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/Symple44/proxmox/refs/heads/main/Misc/build.fonc)

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
APP="SuperSET_BI"
var_disk="20"
var_cpu="4"
var_ram="4096"
var_os="debian"
var_version="12"
POSTGRES_PASSWORD="SuperSET2024!"
SUPERSET_USER_PASSWORD="SuperSET2024!"
ADMIN_PASSWORD="SuperSET2024!"
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

function get_ip() {
  IP=$(pct exec $CT_ID -- hostname -I | awk '{print $1}')
  if [ -z "$IP" ]; then
    msg_error "Impossible de récupérer l'adresse IP"
    exit 1
  fi
}

start
build_container
install_script

get_ip
msg_ok "Installation de SuperSET_BI terminée avec succès!"
echo -e "Accédez à SuperSET_BI à l'adresse : http://${IP}:8088"
