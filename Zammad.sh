#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
               __  
  ___________  ______   ____  __ __  ______
 / ___\_  __ \/  _ \ / ___\|  |  \/  ___/
/ /_/  >  | \(  <_> ) /_/  >  |  /\___ \ 
\___  /|__|   \____/\___  /|____//____  >
/_____/             /_____/            \/ 

EOF
}

header_info
APP="Zammad"
var_disk="30"
var_cpu="4"
var_ram="8192"
var_os="debian"
var_version="12"
POSTGRES_DB="zammad"
POSTGRES_USER="zammad"
POSTGRES_PASSWORD="Zammad2024!"
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
  msg_info "Configuration des paramètres régionaux"
  pct exec "$CTID" -- bash -c "apt install -y locales"
  pct exec "$CTID" -- bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
  pct exec "$CTID" -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
  pct exec "$CTID" -- bash -c "locale-gen en_US.UTF-8"
  msg_ok "Paramètres régionaux configurés"
}

function create_zammad_user() {
  msg_info "Création de l'utilisateur Zammad"

  # Vérification et création du groupe Zammad uniquement s'il n'existe pas
  pct exec "$CTID" -- bash -c "getent group zammad || { groupadd zammad; echo 'Groupe zammad créé'; }"

  # Vérification et création de l'utilisateur Zammad uniquement s'il n'existe pas
  pct exec "$CTID" -- bash -c "id -u zammad &>/dev/null || { useradd zammad -m -d /opt/zammad -s /bin/bash; echo 'Utilisateur zammad créé'; }"

  msg_ok "Utilisateur et groupe Zammad configurés ou déjà existants"
}

function install_postgresql() {
  msg_info "Installation de PostgreSQL"
  pct exec "$CTID" -- bash -c "apt update && apt install -y postgresql postgresql-contrib libpq-dev"
  pct exec "$CTID" -- bash -c "systemctl enable postgresql --now"
  pct exec "$CTID" -- bash -c "sudo -u postgres psql -c \"CREATE DATABASE $POSTGRES_DB;\""
  pct exec "$CTID" -- bash -c "sudo -u postgres psql -c \"CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';\""
  pct exec "$CTID" -- bash -c "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;\""
  msg_ok "PostgreSQL installé et configuré"
}

function install_nodejs() {
  msg_info "Installation de Node.js"
  pct exec "$CTID" -- bash -c "apt install -y ca-certificates curl gnupg"
  pct exec "$CTID" -- bash -c "mkdir -p /etc/apt/keyrings"
  pct exec "$CTID" -- bash -c "curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg"
  pct exec "$CTID" -- bash -c "echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main' > /etc/apt/sources.list.d/nodesource.list"
  pct exec "$CTID" -- bash -c "apt update && apt install -y nodejs"
  msg_ok "Node.js installé"
}

function install_rvm_ruby() {
  msg_info "Installation de RVM et Ruby"
  pct exec "$CTID" -- bash -c "apt install -y curl git patch build-essential bison zlib1g-dev libssl-dev \
                               libxml2-dev libxslt1-dev libyaml-dev autoconf automake libreadline-dev \
                               libtool libgmp-dev libffi-dev libgdbm-dev pkg-config libncurses5-dev gawk"
  pct exec "$CTID" -- bash -c "gpg --keyserver keyserver.ubuntu.com --recv-keys \
                               409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB"
  pct exec "$CTID" -- bash -c "curl -sSL https://get.rvm.io | bash -s stable"
  pct exec "$CTID" -- bash -c "usermod -a -G rvm zammad"
  pct exec "$CTID" -- bash -c "source /usr/local/rvm/scripts/rvm && rvm install 3.2.3 && rvm use 3.2.3 --default"
  pct exec "$CTID" -- bash -c "gem install bundler rake rails"
  msg_ok "RVM et Ruby installés"
}

function install_zammad() {
  msg_info "Téléchargement et installation de Zammad"
  pct exec "$CTID" -- bash -c "cd /opt && wget https://ftp.zammad.com/zammad-latest.tar.gz"
  pct exec "$CTID" -- bash -c "tar -xzf /opt/zammad-latest.tar.gz --strip-components=1 -C /opt/zammad"
  pct exec "$CTID" -- bash -c "chown -R zammad:zammad /opt/zammad && rm -f /opt/zammad-latest.tar.gz"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && bundle config set without \"test development mysql\" && bundle install'"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && yarn install'"
  msg_ok "Zammad installé"
}

function configure_elasticsearch() {
  msg_info "Installation et configuration d'Elasticsearch"
  pct exec "$CTID" -- bash -c "apt update && apt install -y apt-transport-https openjdk-11-jre-headless"
  pct exec "$CTID" -- bash -c "wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -"
  pct exec "$CTID" -- bash -c "echo 'deb https://artifacts.elastic.co/packages/7.x/apt stable main' > /etc/apt/sources.list.d/elastic-7.x.list"
  pct exec "$CTID" -- bash -c "apt update && apt install -y elasticsearch"
  pct exec "$CTID" -- bash -c "systemctl enable elasticsearch --now"
  pct exec "$CTID" -- bash -c "sed -i 's/#cluster.name: my-application/cluster.name: zammad/' /etc/elasticsearch/elasticsearch.yml"
  pct exec "$CTID" -- bash -c "sed -i 's/#network.host: 192.168.0.1/network.host: 127.0.0.1/' /etc/elasticsearch/elasticsearch.yml"
  pct exec "$CTID" -- bash -c "systemctl restart elasticsearch"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && rails r \"Setting.set('es_url', 'http://localhost:9200')\"'"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && rake searchindex:rebuild'"
  msg_ok "Elasticsearch installé et configuré"
}

function install_systemd_service() {
  msg_info "Installation des services systemd pour Zammad"
  pct exec "$CTID" -- bash -c "cd /opt/zammad/script/systemd && ./install-zammad-systemd-services.sh"
  pct exec "$CTID" -- bash -c "systemctl enable zammad --now"
  msg_ok "Services systemd de Zammad installés et démarrés"
}

function main() {
  configure_locales
  create_zammad_user
  install_postgresql
  install_nodejs
  install_rvm_ruby
  install_zammad
  configure_elasticsearch
  install_systemd_service
}

header_info
start
build_container
main
description

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Installation de Zammad terminée avec Elasticsearch!"
echo -e "Accédez à Zammad à l'adresse : http://${IP}:3000"
