#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

set -e  # Arrêter le script en cas d'erreur

function header_info {
  clear
  cat <<"EOF"
    _____                              __   
   / ___/____ ___  ____ _____  ____ _/ /__ 
   \__ \/ __ `__ \/ __ `/ __ \/ __ `/ / _ \
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

function echo_default() {
  echo "Using Default Settings"
  echo "Using Distribution: $var_os"
  echo "Using $var_os Version: $var_version"
  echo "Using Container Type: $CT_TYPE"
  echo "Using Root Password: ${PW:-Automatic Login}"
  echo "Using Container ID: $CT_ID"
  echo "Using Hostname: $HN"
  echo "Using Disk Size: ${DISK_SIZE}GB"
  echo "Allocated Cores $CORE_COUNT"
  echo "Allocated Ram $RAM_SIZE"
  echo "Using Bridge: $BRG"
  echo "Using Static IP Address: $NET"
  echo "Using Gateway IP Address: ${GATE:-Default}"
  echo "Using Apt-Cacher IP Address: ${APT_CACHER_IP:-Default}"
  echo "Disable IPv6: $DISABLEIP6"
  echo "Using Interface MTU Size: ${MTU:-Default}"
  echo "Using DNS Search Domain: ${SD:-Host}"
  echo "Using DNS Server Address: ${NS:-Host}"
  echo "Using MAC Address: ${MAC:-Default}"
  echo "Using VLAN Tag: ${VLAN:-Default}"
  echo "Enable Root SSH Access: $SSH"
  echo "Enable Verbose Mode: $VERB"
}

function install_superset() {
  header_info
  msg_info "Installing dependencies inside the container"

  # Mise à jour et installation des dépendances
  pct exec $CT_ID -- bash -c "apt update && apt upgrade -y"
  pct exec $CT_ID -- bash -c "apt install -y \
    build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server"

  # Démarrer et activer Redis
  msg_info "Starting and enabling Redis"
  pct exec $CT_ID -- bash -c "systemctl enable redis-server && systemctl start redis-server"
  pct exec $CT_ID -- bash -c "systemctl is-active --quiet redis-server && echo 'Redis is running' || (echo 'Redis failed to start'; exit 1)"

  # Créer un environnement virtuel Python pour Superset
  msg_info "Creating Python virtual environment for Superset"
  pct exec $CT_ID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CT_ID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset pillow cachelib[redis]"
  
  # Vérification des installations
  pct exec $CT_ID -- bash -c "source /opt/superset-venv/bin/activate && python3 -c 'import PIL; print(\"Pillow installed\")'"
  pct exec $CT_ID -- bash -c "source /opt/superset-venv/bin/activate && python3 -c 'from cachelib.redis import RedisCache; print(\"RedisCache installed\")'"

  # Configurer Superset
  msg_info "Configuring Superset"
  SECRET_KEY=$(openssl rand -base64 42)
  pct exec $CT_ID -- bash -c "mkdir -p /root/.superset"
  pct exec $CT_ID -- bash -c "echo \"SECRET_KEY = '$SECRET_KEY'\" > /root/.superset/superset_config.py"
  pct exec $CT_ID -- bash -c "cat <<EOF >> /root/.superset/superset_config.py
from cachelib.redis import RedisCache
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_HOST': 'localhost',
    'CACHE_REDIS_PORT': 6379,
    'CACHE_REDIS_DB': 1,
    'CACHE_REDIS_PASSWORD': None,
}
EOF"

  # Initialiser la base de données et créer un administrateur
  msg_info "Initializing Superset database and creating admin user"
  pct exec $CT_ID -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && superset db upgrade"
  pct exec $CT_ID -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password admin"
  
  # Charger des exemples de données
  pct exec $CT_ID -- bash -c "source /opt/superset-venv/bin/activate && export FLASK_APP=superset && superset load_examples"
  msg_ok "Superset database initialized and admin user created"

  # Configurer un service systemd pour Superset
  msg_info "Creating systemd service for Superset"
  pct exec $CT_ID -- bash -c "cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/superset-venv
Environment=\"PATH=/opt/superset-venv/bin\"
ExecStart=/opt/superset-venv/bin/gunicorn --workers 3 --timeout 120 --bind 0.0.0.0:8088 \"superset.app:create_app()\"
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
  pct exec $CT_ID -- bash -c "systemctl daemon-reload && systemctl enable superset && systemctl start superset"
  msg_ok "Superset systemd service created and started"
}

function motd_ssh_custom() {
  msg_info "Customizing MOTD"
  pct exec $CT_ID -- bash -c "echo 'Welcome to your Superset LXC container!' > /etc/motd"
  msg_ok "MOTD customized"
}

header_info
install_superset
motd_ssh_custom
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}:8088${CL} \n"
