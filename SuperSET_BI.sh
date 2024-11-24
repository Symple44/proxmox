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
var_disk="20"
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

function install_dependencies() {
  msg_info "Installing system dependencies"
  pct exec $CTID -- bash -c "apt update && apt install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev curl postgresql"
  if [ $? -ne 0 ]; then
    msg_error "Failed to install dependencies. Check the network or package repository."
    exit 1
  fi
  msg_ok "System dependencies installed successfully"
}

function configure_postgresql() {
  msg_info "Configuring PostgreSQL database for Superset"
  pct exec $CTID -- bash -c "systemctl enable postgresql && systemctl start postgresql"
  pct exec $CTID -- bash -c "sudo -u postgres psql -c 'CREATE DATABASE superset;'"
  pct exec $CTID -- bash -c "sudo -u postgres psql -c \"CREATE USER superset_user WITH PASSWORD 'password';\""
  pct exec $CTID -- bash -c "sudo -u postgres psql -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'"
  if [ $? -ne 0 ]; then
    msg_error "Failed to configure PostgreSQL database"
    exit 1
  fi
  msg_ok "PostgreSQL database configured successfully"
}

function configure_redis() {
  msg_info "Starting Redis service"
  pct exec $CTID -- bash -c "systemctl enable redis-server && systemctl start redis-server"
  pct exec $CTID -- bash -c "redis-cli -h localhost -p 6379 ping || (echo 'Redis connection failed'; exit 1)"
  if [ $? -ne 0 ]; then
    msg_error "Failed to start or connect to Redis"
    exit 1
  fi
  msg_ok "Redis service is running and responsive"
}

function setup_python_venv() {
  msg_info "Creating Python virtual environment"
  pct exec $CTID -- bash -c "python3 -m venv /opt/superset-venv"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && pip install --upgrade pip setuptools wheel"
  if [ $? -ne 0 ]; then
    msg_error "Failed to set up Python virtual environment"
    exit 1
  fi
  msg_ok "Python virtual environment created successfully"
}

function install_superset_libraries() {
  msg_info "Installing Superset and Python libraries"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    pip install apache-superset pillow cachelib[redis] mysqlclient psycopg2-binary pymssql"
  if [ $? -ne 0 ]; then
    msg_error "Failed to install Superset or required libraries"
    exit 1
  fi
  msg_ok "Superset and libraries installed successfully"
}

function configure_superset() {
  msg_info "Configuring Superset"
  SECRET_KEY=$(openssl rand -base64 42)
  pct exec $CTID -- bash -c "mkdir -p /root/.superset"
  pct exec $CTID -- bash -c "cat <<EOF > /root/.superset/superset_config.py
from cachelib.redis import RedisCache

SECRET_KEY = '$SECRET_KEY'
SQLALCHEMY_DATABASE_URI = 'postgresql+psycopg2://superset_user:password@localhost/superset'
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_HOST': 'localhost',
    'CACHE_REDIS_PORT': 6379,
    'CACHE_REDIS_DB': 1,
    'CACHE_REDIS_PASSWORD': None,
}
SUPERSET_WEBSERVER_TIMEOUT = 60
MAPBOX_API_KEY = ''
EOF"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create Superset configuration"
    exit 1
  fi
  msg_ok "Superset configured successfully"
}

function initialize_superset() {
  msg_info "Initializing Superset database"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && superset db upgrade"
  if [ $? -ne 0 ]; then
    msg_error "Failed to initialize Superset database"
    exit 1
  fi
  msg_ok "Superset database initialized successfully"

  msg_info "Creating admin user"
  pct exec $CTID -- bash -c "source /opt/superset-venv/bin/activate && \
    export FLASK_APP=superset && export SUPERSET_CONFIG_PATH=/root/.superset/superset_config.py && superset fab create-admin \
    --username admin --firstname Admin --lastname User --email admin@example.com --password admin"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create admin user"
    exit 1
  fi
  msg_ok "Admin user created successfully"
}

function main() {
  
  install_dependencies
  configure_postgresql
  configure_redis
  setup_python_venv
  install_superset_libraries
  configure_superset
  initialize_superset
}

header_info
start
build_container
main
motd_ssh_custom
description

msg_ok "Superset installation completed successfully!"
echo -e "Access Superset at: ${BL}http://${IP}:8088${CL}"
