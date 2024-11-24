function configure_pg_hba() {
  msg_info "Configuration de l'authentification PostgreSQL"

  # Localiser le fichier pg_hba.conf
  PGB_CONF_PATH=$(pct exec $CTID -- bash -c "find /etc/postgresql -name pg_hba.conf" | tr -d '\r')
  if [ -z "$PGB_CONF_PATH" ]; then
    msg_error "Fichier pg_hba.conf introuvable"
    exit 1
  fi

  # Modifier pg_hba.conf pour activer scram-sha-256
  pct exec $CTID -- bash -c "sed -i 's/local\s*all\s*postgres\s*peer/local all postgres scram-sha-256/' $PGB_CONF_PATH"
  pct exec $CTID -- bash -c "systemctl restart postgresql"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de l'authentification PostgreSQL"
    exit 1
  fi

  msg_ok "Authentification PostgreSQL configurée avec succès"
}

function configure_postgresql() {
  msg_info "Configuration de la base de données PostgreSQL pour Superset"

  # Définir le mot de passe PostgreSQL
  pct exec $CTID -- bash -c "PGPASSWORD='' /usr/bin/psql -U postgres -c \"ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';\""
  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration du mot de passe PostgreSQL. Vérifiez l'authentification et pg_hba.conf."
    exit 1
  fi

  # Créer la base de données Superset
  pct exec $CTID -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' /usr/bin/psql -U postgres -c 'CREATE DATABASE superset;'"
  if [ $? -ne 0 ]; then
    msg_error "Échec de la création de la base de données Superset"
    exit 1
  fi

  # Créer un utilisateur dédié pour Superset
  pct exec $CTID -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' /usr/bin/psql -U postgres -c \"CREATE USER superset_user WITH PASSWORD '$SUPERSET_USER_PASSWORD';\""
  pct exec $CTID -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' /usr/bin/psql -U postgres -c 'GRANT ALL PRIVILEGES ON DATABASE superset TO superset_user;'"

  if [ $? -ne 0 ]; then
    msg_error "Échec de la configuration de l'utilisateur Superset"
    exit 1
  fi

  msg_ok "Base de données PostgreSQL configurée avec succès"
}
