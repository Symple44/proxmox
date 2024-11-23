#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

set -e  # Arrêter le script en cas d'erreur

function header_info {
  clear
  cat <<"EOF"
   _____             __ 
  / ___/____ ___  __/ /_
  \__ \/ __ `__ \/ / __/
 ___/ / / / / / / / /_  
/____/_/ /_/ /_/_/\__/  
EOF
}

header_info
APP="Zammad"
var_disk="30"    # Taille du disque (augmentée à 30 Go pour Zammad)
var_cpu="2"      # Nombre de CPU
var_ram="4096"   # RAM en Mo
var_os="debian"
var_version="12" # Version de Debian
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
  DISABLEIP6="no"
  SSH="yes"
  echo_default
}

function install_dependencies() {
  header_info
  msg_info "Installing Zammad dependencies inside the container"

  pct exec $CTID -- bash -c "apt update && apt upgrade -y"
  pct exec $CTID -- bash -c "apt install -y \
    apt-transport-https ca-certificates curl gnupg software-properties-common \
    build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev redis-server nodejs npm imagemagick \
    graphicsmagick ghostscript libpq-dev libsqlite3-dev"
  
  msg_ok "Dependencies installed successfully"
}

function setup_nodejs() {
  msg_info "Setting up Node.js"
  pct exec $CTID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
  pct exec $CTID -- bash -c "apt install -y nodejs"
  msg_ok "Node.js installed"
}

function download_zammad() {
  msg_info "Downloading Zammad source code"
  pct exec $CTID -- bash -c "cd /opt && wget https://ftp.zammad.com/zammad-latest.tar.gz"
  pct exec $CTID -- bash -c "mkdir -p /opt/zammad && tar -xzf /opt/zammad-latest.tar.gz -C /opt/zammad --strip-components 1"
  pct exec $CTID -- bash -c "chown -R zammad:zammad /opt/zammad && rm -f /opt/zammad-latest.tar.gz"
  msg_ok "Zammad source code downloaded and extracted"
}

function install_rvm_ruby() {
  msg_info "Installing RVM and Ruby"
  pct exec $CTID -- bash -c "curl -sSL https://get.rvm.io | bash -s stable"
  pct exec $CTID -- bash -c "source /usr/local/rvm/scripts/rvm && rvm install 3.2.3 && rvm use 3.2.3 --default"
  msg_ok "RVM and Ruby installed"
}

function configure_zammad() {
  msg_info "Configuring Zammad"
  pct exec $CTID -- bash -c "cd /opt/zammad && bundle config set --local without 'test development'"
  pct exec $CTID -- bash -c "cd /opt/zammad && bundle install"
  pct exec $CTID -- bash -c "cd /opt/zammad && RAILS_ENV=production rake db:migrate"
  pct exec $CTID -- bash -c "cd /opt/zammad && RAILS_ENV=production rake assets:precompile"
  msg_ok "Zammad configured"
}

function setup_postgresql() {
  msg_info "Setting up PostgreSQL"
  pct exec $CTID -- bash -c "apt install -y postgresql"
  pct exec $CTID -- bash -c "sudo -u postgres createuser -s zammad"
  pct exec $CTID -- bash -c "sudo -u postgres createdb -O zammad zammad"
  msg_ok "PostgreSQL configured"
}

function configure_webserver() {
  msg_info "Configuring web server"
  pct exec $CTID -- bash -c "apt install -y apache2"
  # Ajoutez ici une configuration pour Apache si nécessaire
  msg_ok "Web server configured"
}

function setup_motd() {
  msg_info "Customizing MOTD"
  pct exec $CTID -- bash -c "echo 'Welcome to your Zammad LXC container!' > /etc/motd"
  msg_ok "MOTD customized"
}

header_info
start
build_container
default_settings
install_dependencies
setup_nodejs
download_zammad
install_rvm_ruby
configure_zammad
setup_postgresql
configure_webserver
setup_motd

msg_ok "Installation Completed Successfully!"
echo -e "${APP} should be reachable by going to the following URL:\n"
echo -e "  http://${IP}/zammad"
