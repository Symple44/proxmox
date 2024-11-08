#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

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
  pct exec $CTID -- bash -c "apt update && apt upgrade -y"
  pct exec $CTID -- bash -c "apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev libsasl2-dev libldap2-dev python3.11-venv redis-server"
  msg_ok "Dependencies Installed"

  msg_info "Creating Python virtual environment for Superset"
  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip && pip install apache-superset pillow cachelib[redis]"
  msg_ok "Apache Superset, PIL, and Redis cache libraries installed in the container"

  # Générer et configurer une clé secrète sécurisée dans ~/.superset/superset_config.py
  SECRET_KEY=$(openssl rand -base64 42)
  pct exec $CTID -- mkdir -p /root/.superset
  pct exec $CTID -- bash -c "echo \"SECRET_KEY = '$SECRET_KEY'\" > /root/.superset/superset_config.py"

  # Configuration de Redis comme cache pour Superset
  pct exec $CTID -- bash -c "cat <<EOF >> /root/.superset/superset_config.py
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
  msg_ok "Redis cache configuration added to Superset config"

  # Initialiser la base de données et créer l'utilisateur administrateur avec FLASK_APP configuré
  msg_info "Initializing Superset database"
  pct exec $CTID -- bash -c "export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && source /opt/superset-venv/bin/activate && superset db upgrade"
  pct exec $CTID -- bash -c "export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && source /opt/superset-venv/bin/activate && superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password admin"
  msg_ok "Database initialized and admin user created"

  # Charger les exemples de données avec FLASK_APP configuré
  pct exec $CTID -- bash -c "export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && source /opt/superset-venv/bin/activate && superset load_examples"
  msg_ok "Example data loaded"

  # Configurer le service systemd pour Superset
  msg_info "Creating systemd service for Superset in the container"
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
ExecStart=/opt/superset-venv/bin/gunicorn --workers 3 --timeout 120 --bind 0.0.0.0:8088 \"superset.app:create_app()\"
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
  pct exec $CTID -- systemctl daemon-reload
  pct exec $CTID -- systemctl enable superset
  pct exec $CTID -- systemctl start superset
  pct exec $CTID -- systemctl enable redis-server
  pct exec $CTID -- systemctl start redis-server
  msg_ok "Superset and Redis systemd services created and started in the container"
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
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
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
