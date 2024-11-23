#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"
    _____                              __   
   / ___/____ ___  ____ _____  ____ _/ /__ 
   \__ \/ __ __ \/ __ / __ \/ __ / / _ \
  ___/ / / / / / /_/ / / / / / /_/ / /  __/
 /____/_/ /_/ /_/\__,_/_/ /_/\__, /_/\___/ 
                             /____/         
EOF
}

header_info
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
  SSH="yes"
  VERB="no"
  echo_default
}

function install_superset() {
  header_info
  msg_info "Installing dependencies inside the container"

  # Mise à jour des paquets système
  pct exec $CTID -- bash -c "apt update && apt upgrade -y"
  if [ $? -ne 0 ]; then
    msg_error "Failed to update and upgrade packages"
    exit 1
  fi

  # Installation des dépendances système
  pct exec $CTID -- bash -c "apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client mariadb-server libmariadb-dev libmariadb-dev-compat"
  if [ $? -ne 0 ]; then
    msg_error "Failed to install system dependencies"
    exit 1
  fi

  # Vérification de Redis
  msg_info "Starting Redis service"
  pct exec $CTID -- bash -c "systemctl enable redis-server && systemctl start redis-server"
  pct exec $CTID -- bash -c "systemctl is-active --quiet redis-server && echo 'Redis is running' || (echo 'Redis failed to start'; exit 1)"
  pct exec $CTID -- bash -c "redis-cli -h localhost -p 6379 ping || (echo 'Redis connection failed'; exit 1)"
  if [ $? -ne 0 ]; then
    msg_error "Redis setup failed"
    exit 1
  fi
  msg_ok "Redis service is running and responsive"

  # Création de l'environnement virtuel Python
  msg_info "Creating Python virtual environment for Superset"
  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip setuptools wheel"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create or upgrade Python virtual environment"
    exit 1
  fi
  msg_ok "Python virtual environment created successfully"

  # Installation de Superset et des bibliothèques nécessaires
  msg_info "Installing Superset and related libraries"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    pip install apache-superset pillow cachelib[redis] mysqlclient psycopg2-binary"
  if [ $? -ne 0 ]; then
    msg_error "Failed to install Superset and required libraries"
    exit 1
  fi
  msg_ok "Superset and related libraries installed successfully"

  # Génération d'une clé SECRET_KEY sécurisée
  msg_info "Configuring Superset"
  SECRET_KEY=$(openssl rand -base64 42)
  pct exec $CTID -- bash -c "mkdir -p /root/.superset"
  pct exec $CTID -- bash -c "cat <<EOF > /root/.superset/superset_config.py
from cachelib.redis import RedisCache

# Clé secrète pour sécuriser les sessions
SECRET_KEY = '$SECRET_KEY'

# Exemple de configuration pour PostgreSQL
SQLALCHEMY_DATABASE_URI = 'postgresql+psycopg2://superset_user:votre_mot_de_passe@localhost/superset'

# Exemple de configuration pour MySQL
# SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://superset_user:votre_mot_de_passe@your_mysql_server:3306/superset'

# Configuration du cache
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_HOST': 'localhost',
    'CACHE_REDIS_PORT': 6379,
    'CACHE_REDIS_DB': 1,
    'CACHE_REDIS_PASSWORD': None,
}

# Timeout pour les requêtes
SUPERSET_WEBSERVER_TIMEOUT = 60

# Configuration Mapbox (optionnel, ajouter une clé API si nécessaire)
MAPBOX_API_KEY = ''
EOF"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create Superset configuration"
    exit 1
  fi
  msg_ok "Superset configuration created with a secure SECRET_KEY"

  # Initialisation de la base de données
  msg_info "Initializing Superset database"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && superset db upgrade"
  if [ $? -ne 0 ]; then
    msg_error "Failed to initialize Superset database"
    exit 1
  fi
  msg_ok "Superset database initialized successfully"

  # Création de l'utilisateur administrateur
  msg_info "Creating admin user for Superset"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && superset fab create-admin \
    --username admin --firstname Admin --lastname User --email admin@example.com --password admin"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create admin user"
    exit 1
  fi
  msg_ok "Admin user created successfully"

  # Chargement des exemples de données
  msg_info "Loading example data into Superset"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && superset load_examples"
  if [ $? -ne 0 ]; then
    msg_error "Failed to load example data"
    exit 1
  fi
  msg_ok "Example data loaded into Superset"

  # Configuration du service systemd
  msg_info "Creating systemd service for Superset"
  pct exec $CTID -- bash -c "cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/superset-venv
Environment=\"PATH=/opt/superset-venv/bin\"
Environment=\"FLASK_APP=superset\"
Environment=\"SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py\"
ExecStart=/opt/superset-venv/bin/gunicorn --workers 4 --timeout 120 --bind 0.0.0.0:8088 \"superset.app:create_app()\"
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
  pct exec $CTID -- bash -c "systemctl daemon-reload && systemctl enable superset && systemctl start superset"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create and start Superset systemd service"
    exit 1
  fi
  msg_ok "Superset systemd service created and started successfully"
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

header_info
start
build_container
install_superset
motd_ssh_custom
description

# Using the IP variable set by description function to display the final message
msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}:8088${CL} \n"
echo -e "Aucun accès SSH n'est nécessaire pour administrer le conteneur depuis le nœud Proxmox."
