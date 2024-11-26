#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"

__________                                  .___
\____    /____    _____   _____ _____     __| _/
  /     /\__  \  /     \ /     \\__  \   / __ | 
 /     /_ / __ \|  Y Y  \  Y Y  \/ __ \_/ /_/ | 
/_______ (____  /__|_|  /__|_|  (____  /\____ | 
        \/    \/      \/      \/     \/      \/ 
        
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
  msg_info "Configuration des paramètres régionaux dans le conteneur"
  pct exec "$CTID" -- bash -c "apt install -y locales"
  pct exec "$CTID" -- bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
  pct exec "$CTID" -- bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
  pct exec "$CTID" -- bash -c "locale-gen en_US.UTF-8"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration des paramètres régionaux"
    exit 1
  fi
  msg_ok "Paramètres régionaux configurés avec succès"
}

function install_dependencies() {
  header_info
  msg_info "Installation des dépendances système"
  
  pct exec "$CTID" -- bash -c "apt-get update --fix-missing && apt-get upgrade -y"
  pct exec "$CTID" -- bash -c "apt-get install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev default-libmysqlclient-dev curl locales postgresql"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi
  msg_ok "Dépendances système installées avec succès"
}

function configure_postgresql() {
  msg_info "Configuration de PostgreSQL"

  if [ -z "$POSTGRES_DB" ] || [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; then
    msg_error "Variables PostgreSQL manquantes"
    exit 1
  fi

  if ! pct exec "$CTID" -- systemctl is-active postgresql >/dev/null; then
    msg_error "PostgreSQL n'est pas démarré"
    exit 1
  fi

  SQL_SCRIPT=$(mktemp)
  SQL_SCRIPT_DB=$(mktemp)

  cat <<EOF >"$SQL_SCRIPT"
CREATE DATABASE "$POSTGRES_DB";
CREATE USER "$POSTGRES_USER" WITH PASSWORD '$POSTGRES_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" TO "$POSTGRES_USER";

ALTER DATABASE "$POSTGRES_DB" OWNER TO "$POSTGRES_USER";
ALTER SCHEMA public OWNER TO "$POSTGRES_USER";

GRANT ALL PRIVILEGES ON SCHEMA public TO "$POSTGRES_USER";
GRANT CREATE ON SCHEMA public TO "$POSTGRES_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$POSTGRES_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$POSTGRES_USER";
EOF

  cat <<EOF >"$SQL_SCRIPT_DB"
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$POSTGRES_USER";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$POSTGRES_USER";
EOF

  # Copier les fichiers dans le conteneur
  pct push "$CTID" "$SQL_SCRIPT" "/tmp/pgsql_script.sql"
  pct push "$CTID" "$SQL_SCRIPT_DB" "/tmp/pgsql_script_db.sql"

  # Vérification des fichiers avant exécution
  pct exec "$CTID" -- bash -c "[ -f /tmp/pgsql_script.sql ] || { echo 'Fichier /tmp/pgsql_script.sql introuvable'; exit 1; }"
  pct exec "$CTID" -- bash -c "[ -f /tmp/pgsql_script_db.sql ] || { echo 'Fichier /tmp/pgsql_script_db.sql introuvable'; exit 1; }"

  # Exécution des scripts SQL
  pct exec "$CTID" -- bash -c "su - postgres -c 'psql -f /tmp/pgsql_script.sql'" 2>&1 | tee -a /tmp/pgsql_error.log
  pct exec "$CTID" -- bash -c "su - postgres -c 'psql -d \"$POSTGRES_DB\" -f /tmp/pgsql_script_db.sql'" 2>&1 | tee -a /tmp/pgsql_error.log

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration PostgreSQL. Consultez /tmp/pgsql_error.log pour plus de détails"
    exit 1
  fi

  # Nettoyage des fichiers avec des vérifications
  pct exec "$CTID" -- bash -c "if [ -f /tmp/pgsql_script.sql ]; then rm -f /tmp/pgsql_script.sql; else echo '/tmp/pgsql_script.sql non trouvé'; fi"
  pct exec "$CTID" -- bash -c "if [ -f /tmp/pgsql_script_db.sql ]; then rm -f /tmp/pgsql_script_db.sql; else echo '/tmp/pgsql_script_db.sql non trouvé'; fi"

  msg_ok "PostgreSQL configuré avec succès"
}

function install_nodejs() {
  msg_info "Installation de Node.js"
  pct exec "$CTID" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
  pct exec "$CTID" -- bash -c "apt-get install -y nodejs"
  msg_ok "Node.js installé avec succès"
}

function install_rvm_ruby() {
  msg_info "Installation de RVM et Ruby"
  pct exec "$CTID" -- bash -c "gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3"
  pct exec "$CTID" -- bash -c "curl -sSL https://get.rvm.io | bash -s stable"
  pct exec "$CTID" -- bash -c "usermod -a -G rvm zammad"
  pct exec "$CTID" -- bash -c "source /usr/local/rvm/scripts/rvm && rvm install 3.2.3 && rvm use 3.2.3 --default"
  pct exec "$CTID" -- bash -c "gem install bundler rake rails"
  msg_ok "RVM et Ruby installés avec succès"
}

function install_zammad() {
  msg_info "Téléchargement et installation de Zammad"
  pct exec "$CTID" -- bash -c "cd /opt && wget https://ftp.zammad.com/zammad-latest.tar.gz"
  pct exec "$CTID" -- bash -c "mkdir -p /opt/zammad && tar -xzf zammad-latest.tar.gz --strip-components=1 -C /opt/zammad"
  pct exec "$CTID" -- bash -c "chown -R zammad:zammad /opt/zammad && rm -f /opt/zammad-latest.tar.gz"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && bundle config set without \"test development mysql\" && bundle install'"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && yarn install'"
  msg_ok "Zammad installé avec succès"
}

function configure_elasticsearch() {
  msg_info "Installation et configuration d'Elasticsearch"
  pct exec "$CTID" -- bash -c "apt-get install -y apt-transport-https openjdk-11-jre-headless"
  pct exec "$CTID" -- bash -c "wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -"
  pct exec "$CTID" -- bash -c "echo 'deb https://artifacts.elastic.co/packages/7.x/apt stable main' > /etc/apt/sources.list.d/elastic-7.x.list"
  pct exec "$CTID" -- bash -c "apt-get update && apt-get install -y elasticsearch"
  pct exec "$CTID" -- bash -c "systemctl enable elasticsearch --now"
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
  install_dependencies
  configure_locales
  configure_postgresql
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
