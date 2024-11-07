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
var_disk="40"  # Augmentation de la taille du disque pour Superset
var_cpu="2"
var_ram="4096"  # Augmentation de la RAM pour Superset
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

function install_superset {
  msg_info "Installation de Superset (cela peut prendre un certain temps)"
  bash -c "
    apt update -y && \
    apt install -y python3 python3-pip libpq-dev build-essential libssl-dev libffi-dev python3-dev python3-venv && \
    python3 -m venv venv && \
    source venv/bin/activate && \
    pip install apache-superset && \
    superset db upgrade && \
    export FLASK_APP=superset && \
    flask fab create-admin --username admin --firstname admin --lastname admin --email admin@example.com --password admin && \
    superset init && \
    deactivate
  "
  msg_ok "Superset installé avec succès"
}

function build_container() {
  # Vérifier si un conteneur avec le même nom existe déjà
  if [[ $(pct list | grep -c "$CTID") -ne 0 ]]; then
    msg_error "Un conteneur avec l'ID $CTID existe déjà."
    exit 1
  fi

  # Créer le conteneur LXC
  pct create $CTID \
    -hostname $HN \
    -net0 name=eth0,bridge=$BRG,gw=$GATE,hwaddr=$MAC,ip=$NET,mtu=$MTU,tag=$VLAN,type=veth \
    -ostype $var_os \
    -rootfs local-lvm,size=$DISK_SIZE,ssd=$SD \
    -cpulimit $CPULIMIT \
    -cores $CORE_COUNT \
    -memory $RAM_SIZE \
    -onboot 1 \
    -protection 1 \
    -unique 1 \
    -unprivileged 0

  # Démarrer le conteneur
  pct start $CTID

  # Attendre que le conteneur soit démarré
  while ! pct status $CTID --wait; do
    sleep 1
  done

  # Installer Superset dans le conteneur
  pct exec $CTID -- bash -c "
    echo 'deb http://deb.debian.org/debian $var_version main contrib non-free' > /etc/apt/sources.list && \
    apt update -y && \
    apt install -y curl wget sudo
  "
  pct push $CTID /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys --perms 0600
  pct exec $CTID -- bash -c "
    apt update -y && \
    install_superset
  "

  # Activer et démarrer le service Superset
  pct exec $CTID -- bash -c "
    source venv/bin/activate && \
    superset run -h 0.0.0.0 -p 8088 --with-threads --reload --debugger
  "
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}:8088${CL} \n"
