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
  SSH="no"
  VERB="no"
  echo_default
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
description

# Using the IP variable set by description function to display the final message
msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}:8088${CL} \n"
echo -e "Authentication is disabled for automatic login."
