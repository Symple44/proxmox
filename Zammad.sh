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
POSTGRES_PASSWORD="Zammad2024"
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

function install_dependencies() {
  header_info
  msg_info "Installation des dépendances système"
  
  pct exec "$CTID" -- bash -c "apt-get update --fix-missing && apt-get upgrade -y"
  pct exec "$CTID" -- bash -c "apt-get install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev default-libmysqlclient-dev curl locales postgresql git libvips-dev libjpeg-dev libpng-dev libtiff-dev \
    zlib1g-dev libimlib2 libimlib2-dev"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi
  msg_ok "Dépendances système installées avec succès"
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

function create_zammad_user() {
  msg_info "Création de l'utilisateur Zammad"

  # Vérifier et créer le groupe Zammad
  pct exec "$CTID" -- bash -c "getent group zammad || groupadd zammad"

  # Vérifier et créer l'utilisateur Zammad, en le liant au groupe existant
  pct exec "$CTID" -- bash -c "id -u zammad &>/dev/null || useradd -m -d /opt/zammad -s /bin/bash -g zammad zammad"

  msg_ok "Utilisateur et groupe Zammad configurés ou déjà existants"
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
CREATE DATABASE "$POSTGRES_DB" ENCODING 'UTF8' TEMPLATE template0;
CREATE USER "$POSTGRES_USER" WITH PASSWORD '$POSTGRES_PASSWORD' ;
GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" TO "$POSTGRES_USER";
ALTER USER "$POSTGRES_USER" CREATEDB;

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
  # Importer les clés GPG nécessaires pour RVM
  pct exec "$CTID" -- bash -c "gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB || \
  (curl -sSL https://rvm.io/mpapis.asc | gpg --import - && curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -)"
  # Installer RVM
  pct exec "$CTID" -- bash -c "curl -sSL https://get.rvm.io | bash -s stable"
  # Ajouter l'utilisateur zammad au groupe rvm
  pct exec "$CTID" -- bash -c "usermod -a -G rvm zammad"
  # Installer Ruby via RVM
  pct exec "$CTID" -- bash -c "source /usr/local/rvm/scripts/rvm && rvm install 3.2.4 && rvm use 3.2.4 --default"
  # Installer les gems nécessaires
  pct exec "$CTID" -- bash -c "source /usr/local/rvm/scripts/rvm && gem install bundler rake rails"
  msg_ok "RVM et Ruby installés avec succès"
}


function install_zammad() {
  msg_info "Téléchargement et installation de Zammad"
  # Téléchargement du fichier Zammad
  pct exec "$CTID" -- bash -c "wget -O /tmp/zammad-latest.tar.gz https://ftp.zammad.com/zammad-latest.tar.gz"
  # Vérifier si le fichier a été téléchargé
  pct exec "$CTID" -- bash -c "if [ ! -f /tmp/zammad-latest.tar.gz ]; then echo 'Fichier non trouvé'; exit 1; fi"
  # Extraire le fichier téléchargé
  pct exec "$CTID" -- bash -c "mkdir -p /opt/zammad && tar -xzf /tmp/zammad-latest.tar.gz --strip-components=1 -C /opt/zammad"
  # Nettoyer après l'installation
  pct exec "$CTID" -- bash -c "rm -f /tmp/zammad-latest.tar.gz"
  msg_ok "Zammad installé et configuré pour la production"
}
function configure_zammad() {
  msg_info "Configuration de Zammad pour la production"
  
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && RAILS_ENV=production bundle install --jobs 4 --retry 3'"

  # Configurer la base de données
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && RAILS_ENV=production rake db:create db:migrate'"

  # Précompiler les assets
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && RAILS_ENV=production rake assets:precompile'"

  # Configurer Elasticsearch pour Zammad
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && RAILS_ENV=production rails r \"Setting.set('es_url', 'http://localhost:9200')\"'"
  pct exec "$CTID" -- bash -c "su - zammad -c 'cd /opt/zammad && RAILS_ENV=production rake searchindex:rebuild'"

  msg_ok "Zammad configuré pour la production"
}


function configure_elasticsearch() {
  msg_info "Installation et configuration d'Elasticsearch"

  # Ajouter les dépôts nécessaires
  pct exec "$CTID" -- bash -c "apt-get update"
  
  # Installer Elasticsearch et ses dépendances
  pct exec "$CTID" -- bash -c "apt-get install -y apt-transport-https openjdk-17-jre-headless && \
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - && \
    echo 'deb https://artifacts.elastic.co/packages/7.x/apt stable main' > /etc/apt/sources.list.d/elastic-7.x.list && \
    apt-get update && apt-get install -y elasticsearch && \
    systemctl enable elasticsearch --now && \
    sed -i 's/#network.host: 192.168.0.1/network.host: 127.0.0.1/' /etc/elasticsearch/elasticsearch.yml && \
    systemctl restart elasticsearch"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration d'Elasticsearch dans Zammad"
    exit 1
  fi
  msg_ok "Elasticsearch installé et configuré"
}
function configure_database_yml() {
  msg_info "Configuration du fichier database.yml"

  # Vérifier si le fichier source existe
  pct exec "$CTID" -- bash -c "[ -f /opt/zammad/config/database/database.yml ] || { echo 'Source file missing'; exit 1; }"

  # Copier le fichier source vers le bon emplacement
  pct exec "$CTID" -- bash -c "cp /opt/zammad/config/database/database.yml /opt/zammad/config/database.yml"

  # Décommenter et remplacer les balises nécessaires
  pct exec "$CTID" -- bash -c "sed -i 's/# *adapter:.*/adapter: postgresql/' /opt/zammad/config/database.yml"
  pct exec "$CTID" -- bash -c "sed -i 's/# *database:.*/database: $POSTGRES_DB/' /opt/zammad/config/database.yml"
  pct exec "$CTID" -- bash -c "sed -i 's/# *user:.*/user: $POSTGRES_USER/' /opt/zammad/config/database.yml"
  pct exec "$CTID" -- bash -c "sed -i 's/# *password:.*/password: $POSTGRES_PASSWORD/' /opt/zammad/config/database.yml"
  pct exec "$CTID" -- bash -c "sed -i 's/# *host:.*/host: localhost/' /opt/zammad/config/database.yml"

  # Ajouter ou remplacer la ligne pour `template`
  pct exec "$CTID" -- bash -c "grep -q 'template:' /opt/zammad/config/database.yml && \
    sed -i 's/# *template:.*/template: template0/' /opt/zammad/config/database.yml || \
    echo 'template: template0' >> /opt/zammad/config/database.yml"

  # Ajuster les permissions
  pct exec "$CTID" -- bash -c "chown zammad:zammad /opt/zammad/config/database.yml"
  pct exec "$CTID" -- bash -c "chmod 600 /opt/zammad/config/database.yml"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de database.yml"
    exit 1
  fi

  msg_ok "Fichier database.yml configuré avec succès"
}


function install_systemd_service() {
  msg_info "Installation des services systemd pour Zammad"
  pct exec "$CTID" -- bash -c "cd /opt/zammad/script/systemd && ./install-zammad-systemd-services.sh"
  pct exec "$CTID" -- bash -c "systemctl enable zammad --now"
  msg_ok "Services systemd de Zammad installés et démarrés"
}

function motd_ssh_custom() {
  msg_info "Customizing MOTD and SSH access"
  # Customize MOTD with Superset specific message
  pct exec $CTID -- bash -c "echo 'Welcome to your Zammad LXC container!' > /etc/motd"
  
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
  create_zammad_user 
  configure_postgresql
  install_nodejs
  install_rvm_ruby
  install_zammad
  configure_database_yml
  configure_zammad
  configure_elasticsearch
  install_systemd_service
}

header_info
start
build_container
main
motd_ssh_custom
description

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Installation de Zammad terminée avec Elasticsearch!"
echo -e "Accédez à Zammad à l'adresse : http://${IP}:3000"
