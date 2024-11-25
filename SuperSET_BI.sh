#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
                         __  
  ________ ________  ___________  ______ _____/  |_ 
 /  ___/  |  \____ \_/ __ \_  __ \/  ___// __ \  __\
 \___ \|  |  /  |_> >  ___/|  | \/\___ \\  ___/|  |  
/____  >____/|   __/ \___  >__|  /____  >\___  >__|  
     \/      |__|        \/          \/     \/       

EOF
}

header_info
APP="Superset"
var_disk="20"
var_cpu="4"
var_ram="4096"
var_os="debian"
var_version="12"
ADMIN_PASSWORD="Superset2024!"
POSTGRES_DB="superset"
POSTGRES_USER="superset_user"
POSTGRES_PASSWORD="Postgres2024"
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

  # Injection des commandes générales
  pct exec "$CTID" -- bash -c "su - postgres -c 'psql -f $SQL_SCRIPT'" 2>/tmp/pgsql_error.log

  # Commandes spécifiques à la base $POSTGRES_DB
  SQL_SCRIPT_DB=$(mktemp)
  cat <<EOF >"$SQL_SCRIPT_DB"
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$POSTGRES_USER";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$POSTGRES_USER";
EOF

  pct exec "$CTID" -- bash -c "su - postgres -c 'psql -d \"$POSTGRES_DB\" -f $SQL_SCRIPT_DB'" 2>>/tmp/pgsql_error.log

  # Nettoyage des fichiers temporaires
  rm -f "$SQL_SCRIPT" "$SQL_SCRIPT_DB"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration PostgreSQL. Consultez /tmp/pgsql_error.log pour plus de détails"
    exit 1
  fi

  msg_ok "PostgreSQL configuré avec succès"
}

function install_superset() {
  msg_info "Installation de Superset"
  
  pct exec "$CTID" -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de Superset"
    exit 1
  fi
  msg_ok "Superset installé avec succès"

  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && pip install psycopg2-binary"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des pilotes PostgreSQL"
    exit 1
  fi
  msg_ok "Pilotes PostgreSQL installés avec succès"

  pct exec "$CTID" -- bash -c "cat > /opt/superset-venv/superset_config.py << EOF
import os
SECRET_KEY = 'thisISaSECRET_1234'
SQLALCHEMY_DATABASE_URI = 'postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}'
SQLALCHEMY_TRACK_MODIFICATIONS = False
EOF"

  pct exec "$CTID" -- bash -c "[ -f /opt/superset-venv/superset_config.py ]"
  if [ $? -ne 0 ]; then
    msg_error "Le fichier de configuration Superset n'a pas été créé"
    exit 1
  fi

  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && superset db upgrade"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la mise à jour de la base de données Superset"
    exit 1
  fi

  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && superset fab create-admin --username admin --password $ADMIN_PASSWORD"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de l'utilisateur administrateur Superset"
    exit 1
  fi

  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && superset init"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'initialisation de Superset"
    exit 1
  fi
  msg_ok "Superset initialisé avec succès"
}

function configure_firewall() {
  msg_info "Configuration du pare-feu et autorisation du port 8088"
  pct exec "$CTID" -- bash -c "if ! command -v ufw >/dev/null; then apt install -y ufw; fi"
  pct exec "$CTID" -- bash -c "ufw allow 8088 && ufw --force enable"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration du pare-feu"
    exit 1
  fi
  msg_ok "Pare-feu configuré avec succès"
}

function motd_ssh_custom() {
  msg_info "Personnalisation du MOTD et configuration de l'accès SSH"
  pct exec "$CTID" -- bash -c "echo 'Bienvenue dans votre conteneur Superset LXC !' > /etc/motd"
}

function main() {
  install_dependencies
  configure_locales
  configure_postgresql
  install_superset
  configure_firewall
}

header_info
start
build_container
main
motd_ssh_custom
description

msg_ok "Installation de Superset terminée avec succès!"
echo -e "Accédez à Superset à l'adresse : http://${IP}:8088"
