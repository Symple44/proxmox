#!/usr/bin/env bash

set -e

POSTGRES_PASSWORD="Superset2024!"
SUPERSET_USER_PASSWORD="Superset2024!"
ADMIN_PASSWORD="Superset2024!"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os
header_info

msg_info "Mise à jour des dépôts et installation des dépendances"
apt-get update --fix-missing && apt-get upgrade -y
apt-get install -y locales build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
  libsasl2-dev libldap2-dev python3.11-venv redis-server libpq-dev mariadb-client libmariadb-dev libmariadb-dev-compat \
  freetds-dev unixodbc-dev curl postgresql
msg_ok "Dépendances installées avec succès"

msg_info "Configuration des paramètres régionaux"
echo 'LANG=en_US.UTF-8' > /etc/default/locale
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen en_US.UTF-8
msg_ok "Paramètres régionaux configurés"

msg_info "Démarrage et configuration de PostgreSQL"
systemctl enable postgresql
systemctl start postgresql
sed -i 's/local\s*all\s*postgres\s*peer/local all postgres scram-sha-256/' /etc/postgresql/*/main/pg_hba.conf
systemctl restart postgresql

# Définir un mot de passe pour l'utilisateur postgres
psql -U postgres -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';"
msg_ok "PostgreSQL configuré avec succès"

msg_info "Création de la base de données et des utilisateurs pour Superset"
psql -U postgres -c 'CREATE DATABASE superset;'
psql -U postgres -c "CREATE USER superset_user WITH PASSWORD '$SUPERSET_USER_PASSWORD';"
psql -U postgres -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'
msg_ok "Base de données et utilisateurs configurés"

msg_info "Installation de Superset"
python3 -m venv /opt/superset-venv
source /opt/superset-venv/bin/activate
pip install --upgrade pip
pip install apache-superset
msg_ok "Superset installé avec succès"

msg_info "Initialisation de Superset"
source /opt/superset-venv/bin/activate
superset db upgrade
superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname User \
  --email admin@example.com \
  --password $ADMIN_PASSWORD
superset init
msg_ok "Superset initialisé avec succès"

msg_info "Création d'un service systemd pour Superset"
cat <<EOF >/etc/systemd/system/superset.service
[Unit]
Description=Superset BI Service
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
msg_ok "Service systemd Superset créé et démarré"

msg_ok "Installation de SuperSET_BI terminée avec succès!"
echo -e "Accédez à SuperSET_BI à l'adresse : http://<IP>:8088"

