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
    freetds-dev unixodbc-dev curl postgresql locales"
  pct exec $CTID -- bash -c "locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
  if [ $? -ne 0 ]; then
    msg_error "Failed to install dependencies. Check the network or package repository."
    exit 1
  fi
  msg_ok "System dependencies installed successfully"
}

function configure_pg_authentication() {
  msg_info "Configuring PostgreSQL authentication"

  # Modifier pg_hba.conf pour autoriser md5 authentication
  pct exec $CTID -- bash -c "sed -i 's/local\s*all\s*postgres\s*peer/local all postgres md5/' /etc/postgresql/*/main/pg_hba.conf"
  pct exec $CTID -- bash -c "systemctl restart postgresql"

  # Définir un mot de passe pour l'utilisateur postgres
  pct exec $CTID -- bash -c "psql -U postgres -c \"ALTER USER postgres PASSWORD 'postgres';\""
  if [ $? -ne 0 ]; then
    msg_error "Failed to configure PostgreSQL authentication"
    exit 1
  fi

  msg_ok "PostgreSQL authentication configured successfully"
}

function configure_postgresql() {
  msg_info "Configuring PostgreSQL database for Superset"

  # Start PostgreSQL service
  pct exec $CTID -- bash -c "systemctl enable postgresql && systemctl start postgresql"

  # Ensure the postgres user exists
  pct exec $CTID -- bash -c "psql -U postgres -c '\du'" || \
    pct exec $CTID -- bash -c "createuser --superuser postgres"

  # Create Superset database
  pct exec $CTID -- bash -c "psql -U postgres -c 'CREATE DATABASE superset;'"
  if [ $? -ne 0 ]; then
    msg_error "Failed to create the Superset database"
    exit 1
  fi

  # Create and configure the superset_user
  pct exec $CTID -- bash -c "psql -U postgres -c \"CREATE USER superset_user WITH PASSWORD 'password';\""
  pct exec $CTID -- bash -c "psql -U postgres -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'"
  if [ $? -ne 0 ]; then
    msg_error "Failed to configure the Superset user"
    exit 1
  fi

  msg_ok "PostgreSQL database configured successfully"
}

function main() {
  install_dependencies
  configure_pg_authentication
  configure_postgresql
}

header_info
start
build_container
main
motd_ssh_custom
description

msg_ok "Superset installation completed successfully!"
echo -e "Access Superset at: ${BL}http://${IP}:8088${CL}"
