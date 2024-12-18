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

function install_superset() {
  msg_info "Installation de Superset"
  
  pct exec "$CTID" -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation de Superset"
    exit 1
  fi
  msg_ok "Superset installé avec succès"

  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && pip install psycopg2-binary pillow"
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances Python"
    exit 1
  fi
  msg_ok "Dépendances Python installées avec succès"

  # Générer une clé sécurisée
  SECRET_KEY=$(openssl rand -base64 42)

  # Créer le fichier superset_config.py avec la langue française
  pct exec "$CTID" -- bash -c "cat > /opt/superset-venv/superset_config.py <<EOF
import os

SECRET_KEY = '${SECRET_KEY}'
SQLALCHEMY_DATABASE_URI = 'postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}'
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Configuration pour la langue française
BABEL_DEFAULT_LOCALE = 'fr'
BABEL_DEFAULT_FOLDER = 'translations'
LANGUAGES = {
    'fr': {'flag': 'fr', 'name': 'French'},
    'en': {'flag': 'us', 'name': 'English'}
}
EOF"

  # Ajouter FLASK_APP et SUPERSET_CONFIG_PATH à l'environnement virtuel
  pct exec "$CTID" -- bash -c "echo 'export FLASK_APP=superset' >> /opt/superset-venv/bin/activate"
  pct exec "$CTID" -- bash -c "echo 'export SUPERSET_CONFIG_PATH=/opt/superset-venv/superset_config.py' >> /opt/superset-venv/bin/activate"

  # Configurer les paramètres régionaux
  pct exec "$CTID" -- bash -c "export LANG=fr_FR.UTF-8"
  pct exec "$CTID" -- bash -c "export LC_ALL=fr_FR.UTF-8"

  # Effectuer les migrations de base de données
  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && superset db upgrade"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la mise à jour de la base de données Superset"
    exit 1
  fi

  # Créer un utilisateur administrateur
  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && superset fab create-admin --username admin --password $ADMIN_PASSWORD --firstname Superset --lastname Admin --email admin@example.com"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de l'utilisateur administrateur Superset"
    exit 1
  fi

  # Initialiser Superset
  pct exec "$CTID" -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && superset init"
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

function configure_superset_service() {
  msg_info "Création d'un service systemd pour Superset"

  # Créez un fichier de service systemd pour Superset
  pct exec "$CTID" -- bash -c "cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/superset-venv
Environment='FLASK_APP=superset'
Environment='SUPERSET_CONFIG_PATH=/opt/superset-venv/superset_config.py'
ExecStart=/opt/superset-venv/bin/superset run -h 0.0.0.0 -p 8088
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

  # Recharge systemd pour prendre en compte le nouveau service
  pct exec "$CTID" -- systemctl daemon-reload

  # Activer et démarrer le service Superset
  pct exec "$CTID" -- systemctl enable superset
  pct exec "$CTID" -- systemctl start superset

  # Vérifiez si le service a démarré correctement
  if pct exec "$CTID" -- systemctl is-active superset >/dev/null; then
    msg_ok "Service Superset configuré et démarré avec succès"
  else
    msg_error "Le service Superset n'a pas pu être démarré"
    exit 1
  fi
}


function motd_ssh_custom() {
  msg_info "Customizing MOTD and SSH access"
  # Customize MOTD with Superset specific message
  pct exec $CTID -- bash -c "echo 'Welcome to your Superset LXC container!' > /etc/motd"
  
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
  configure_postgresql
  install_superset
  configure_firewall
  configure_superset_service
}

header_info
start
build_container
main
motd_ssh_custom
description

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Installation de Superset terminée avec succès!"
echo -e "Accédez à Superset à l'adresse : http://${IP}:8088"
