#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

set -e 

function header_info {
  clear
  cat <<"EOF"
  _____                                   _ 
 |__  /__ _ _ __ ___  _ __ ___   __ _  __| |
   / // _` | '_ ` _ \| '_ ` _ \ / _` |/ _` |
  / /| (_| | | | | | | | | | | | (_| | (_| |
 /____\__,_|_| |_| |_|_| |_| |_|\__,_|\__,_|
                                             
EOF
}

header_info
APP="Zammad"
var_disk="20"
var_cpu="2"
var_ram="4096"
var_os="debian"
var_version="11"
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
  GATE="  " 
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

function install_zammad() {
  header_info
  msg_info "Installing Zammad dependencies inside the container"
  pct exec $CTID -- bash -c "apt update && apt upgrade -y"
  pct exec $CTID -- bash -c "apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common"

  # Ajouter le dépôt Zammad
  pct exec $CTID -- bash -c "curl -fsSL https://dl.packager.io/srv/zammad/zammad/key | apt-key add -"
  pct exec $CTID -- bash -c "add-apt-repository \"deb [arch=amd64] https://dl.packager.io/srv/zammad/zammad/stable/debian/ \$(lsb_release -cs) main\""

  # Installer Zammad
  pct exec $CTID -- bash -c "apt update"
  pct exec $CTID -- bash -c "apt install -y zammad"

  # Configuration de la base de données PostgreSQL
  msg_info "Configuring PostgreSQL database"
  pct exec $CTID -- bash -c "sudo -u postgres createuser -s zammad" 
  pct exec $CTID -- bash -c "sudo -u postgres createdb -O zammad zammad"
  #  (Le script d'installation de Zammad vous demandera le mot de passe de l'utilisateur PostgreSQL "zammad". Assurez-vous de le noter.)

  # Configuration du serveur web Apache2
  msg_info "Configuring Apache2 web server" 
  # (Normalement, l'installation de Zammad configure automatiquement Apache2. 
  #  Vous pouvez ajouter ici des commandes pour personnaliser la configuration d'Apache2 si nécessaire.)

  # Configuration du serveur de mail Postfix
  msg_info "Configuring Postfix mail server"
  pct exec $CTID -- bash -c "debconf-set-selections <<< 'postfix postfix/mailname string $HN'"
  pct exec $CTID -- bash -c "debconf-set-selections <<< 'postfix postfix/main_mailer_type string 'Internet Site''"
  pct exec $CTID -- bash -c "apt install -y postfix"
  # (Vous devrez peut-être configurer davantage Postfix pour qu'il fonctionne correctement avec votre fournisseur de messagerie.)

  msg_ok "Zammad installed successfully"
}

function motd_ssh_custom() {
  msg_info "Customizing MOTD"
  pct exec $CTID -- bash -c "echo 'Welcome to your Zammad LXC container!' > /etc/motd"
  msg_ok "MOTD customized"
}

header_info
start
build_container
install_zammad
motd_ssh_custom
description

# Using the IP variable set by description function to display the final message
msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}/zammad${CL} \n"
