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
  SSH="yes"  # Activer SSH pour le conteneur
  VERB="no"
  echo_default
}

function configure_ssh_access() {
  # Générer une paire de clés SSH si elle n'existe pas déjà
  if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
    echo "Clé SSH générée."
  else
    echo "Clé SSH existante trouvée."
  fi

  # Copier la clé publique dans le conteneur pour autoriser l'accès sans mot de passe
  pct exec $CTID -- mkdir -p /root/.ssh
  pct exec $CTID -- bash -c "echo '$(cat ~/.ssh/id_rsa.pub)' >> /root/.ssh/authorized_keys"
  pct exec $CTID -- chmod 600 /root/.ssh/authorized_keys
  pct exec $CTID -- chmod 700 /root/.ssh

  # Configurer SSH pour autoriser l'authentification par clé publique uniquement
  pct exec $CTID -- bash -c "echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config"
  pct exec $CTID -- bash -c "echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config"
  pct exec $CTID -- systemctl restart ssh
  echo "Configuration SSH sans mot de passe appliquée."
}

function install_superset() {
  header_info
  msg_info "Updating system and installing dependencies"
  apt update && apt upgrade -y
  apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev libsasl2-dev libldap2-dev libssl-dev python3.11-venv
  msg_ok "Dependencies Installed"

  msg_info "Creating Python virtual environment for Superset"
  python3 -m venv /opt/superset-venv
  source /opt/superset-venv/bin/activate
  msg_ok "Python virtual environment created and activated"

  msg_info "Updating pip and installing Apache Superset"
  pip install --upgrade pip
  pip install apache-superset
  msg_ok "Apache Superset installed"

  # Générer et configurer une clé secrète sécurisée dans ~/.superset/superset_config.py
  SECRET_KEY=$(openssl rand -base64 42)
  mkdir -p /root/.superset
  cat <<EOF >/root/.superset/superset_config.py
# Configuration sécurisée de Superset
SECRET_KEY = "$SECRET_KEY"
EOF

  # Définir les variables d'environnement pour la configuration
  export FLASK_APP=superset
  export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py
  msg_ok "Secure SECRET_KEY configured in /root/.superset/superset_config.py"

  msg_info "Initializing Superset database"
  superset db upgrade
  msg_ok "Database initialized"

  msg_info "Creating admin user for Superset"
  superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password admin
  msg_ok "Admin user created"

  msg_info "Loading example data"
  superset load_examples
  msg_ok "Example data loaded"

  msg_info "Configuring Superset to use Gunicorn"
  pip install gunicorn
  msg_ok "Gunicorn installed"

  msg_info "Creating systemd service for Superset"
  cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/opt/superset-venv
Environment="PATH=/opt/superset-venv/bin"
Environment="FLASK_APP=superset"
Environment="SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py"
ExecStart=/opt/superset-venv/bin/gunicorn --workers 3 --timeout 120 --bind 0.0.0.0:8088 "superset.app:create_app()"
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable superset
  systemctl start superset
  msg_ok "Superset systemd service created and started"
}

header_info
start
build_container
install_superset
configure_ssh_access  # Configuration de l'accès SSH sans mot de passe
description

# Using the IP variable set by description function to display the final message
msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}:8088${CL} \n"
echo -e "Authentication is disabled for automatic login."
