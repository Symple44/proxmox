#!/usr/bin/env bash

POSTGRES_PASSWORD="Superset2024!"
SUPERSET_USER_PASSWORD="Superset2024!"
ADMIN_PASSWORD="Superset2024!"

function configure_locales() {
  msg_info "Configuration des paramètres régionaux dans le conteneur"
  apt install -y locales
  echo 'LANG=en_US.UTF-8' > /etc/default/locale
  echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
  locale-gen en_US.UTF-8
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration des paramètres régionaux"
    exit 1
  fi
  msg_ok "Paramètres régionaux configurés avec succès"
}

function install_dependencies() {
  msg_info "Installation des dépendances système"
  apt-get update --fix-missing && apt-get upgrade -y
  apt-get install -y build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
    freetds-dev unixodbc-dev curl postgresql locales
  if [ $? -ne 0 ]; then
    msg_error "Échec de l'installation des dépendances"
    exit 1
  fi
  msg_ok "Dépendances système installées avec succès"
}

function install_postgresql() {
  msg_info "Installation et démarrage de PostgreSQL"
  apt install -y postgresql
  systemctl enable postgresql && systemctl start postgresql
  if [ $? -ne 0 ]; then
    msg_error "PostgreSQL n'a pas démarré correctement"
    exit 1
  fi
  msg_ok "PostgreSQL installé et démarré avec succès"
}

function configure_postgresql() {
  msg_info "Configuration de PostgreSQL"
  sed -i 's/local\s*all\s*postgres\s*peer/local all postgres scram-sha-256/' /etc/postgresql/*/main/pg_hba.conf
  systemctl restart postgresql
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de l'authentification PostgreSQL"
    exit 1
  fi
  psql -U postgres -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration du mot de passe PostgreSQL"
    exit 1
  fi
  psql -U postgres -c 'CREATE DATABASE superset;'
  psql -U postgres -c "CREATE USER superset_user WITH PASSWORD '$SUPERSET_USER_PASSWORD';"
  psql -U postgres -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'
  msg_ok "PostgreSQL configuré avec succès"
}

function install_superset() {
  msg_info "Installation de Superset"
  python3 -m venv /opt/superset-venv
  source /opt/superset-venv/bin/activate
  pip install --upgrade pip && pip install apache-superset
  superset db upgrade
  superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password $ADMIN_PASSWORD
  superset init
  msg_ok "Superset installé et initialisé avec succès"
}

function main() {
  configure_locales
  install_dependencies
  install_postgresql
  configure_postgresql
  install_superset
}

main
