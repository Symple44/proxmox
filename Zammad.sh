#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

set -e  # Arrêter le script en cas d'erreur

function header_info {
  clear
  cat <<"EOF"
   _____             __ 
  / ___/____ ___  __/ /_
  \__ \/ __ `__ \/ / __/
 ___/ / / / / / / / /_  
/____/_/ /_/ /_/_/\__/  
EOF
}

header_info
APP="Zammad"
var_disk="30"  # Ajuster la taille du disque si nécessaire (augmentée à 30 Go)
var_cpu="2"   # Ajuster le nombre de CPU si nécessaire
var_ram="4096" # Ajuster la RAM si nécessaire
var_os="debian"
var_version="12" # Version de Debian mise à jour
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
  BRG="vmbr0"  # Ajuster le pont réseau si nécessaire
  NET="dhcp"   # Utiliser DHCP pour le réseau
  GATE=""      # Pas de passerelle par défaut avec DHCP
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

function install_zammad() {
  header_info
  msg_info "Installing Zammad dependencies inside the container"
  pct exec $CTID -- bash -c "apt update && apt upgrade -y"

  # Installer les dépendances nécessaires pour compiler Zammad à partir des sources
  pct exec $CTID -- bash -c "apt install -y \
    apt-transport-https ca-certificates curl gnupg2 software-properties-common \
    build-essential libssl-dev libffi-dev python3 python3-pip python3-dev \
    libsasl2-dev libldap2-dev python3.11-venv redis-server \
    nodejs npm imagemagick graphicsmagick ghostscript \
    libpq-dev libmariadbclient-dev libmysqlclient-dev \
    freetds-dev unixodbc-dev libsqlite3-dev" 

  # Installer Node.js
  msg_info "Installing Node.js"
  pct exec $CTID -- bash -c "apt install -y ca-certificates curl gnupg"
  pct exec $CTID -- bash -c "mkdir -p /etc/apt/keyrings"
  pct exec $CTID -- bash -c "curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg"
  pct exec $CTID -- bash -c "NODE_MAJOR=20; echo \"deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_\$NODE_MAJOR.x nodistro main\" | tee /etc/apt/sources.list.d/nodesource.list"
  pct exec $CTID -- bash -c "apt update"
  pct exec $CTID -- bash -c "apt install -y nodejs"

  # Télécharger et extraire le code source de Zammad
  msg_info "Downloading and extracting Zammad source code"
  pct exec $CTID -- bash -c "cd /opt && wget https://ftp.zammad.com/zammad-latest.tar.gz"
  pct exec $CTID -- bash -c "cd /opt && tar -xzf zammad-latest.tar.gz --strip-components 1 -C zammad"
  pct exec $CTID -- bash -c "cd /opt && chown -R zammad:zammad zammad/"
  pct exec $CTID -- bash -c "cd /opt && rm -f zammad-latest.tar.gz"

  # Installer RVM
  msg_info "Installing RVM"
  pct exec $CTID -- bash -c "apt install -y curl git patch build-essential bison zlib1g-dev libssl-dev libxml2-dev libxml2-dev autotools-dev libxslt1-dev libyaml-0-2 autoconf automake libreadline-dev libyaml-dev libtool libgmp-dev libgdbm-dev libncurses5-dev pkg-config libffi-dev libimlib2-dev gawk"
  pct exec $CTID -- bash -c "gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB"
  pct exec $CTID -- bash -c "curl -L https://get.rvm.io | bash -s stable"

  # Définir les variables d'environnement
  msg_info "Setting environment variables"
  pct exec $CTID -- bash -c "echo \"export RAILS_ENV=production\" >> /opt/zammad/.bashrc"
  pct exec $CTID -- bash -c "echo \"export RAILS_SERVE_STATIC_FILES=true\" >> /opt/zammad/.bashrc"
  pct exec $CTID -- bash -c "echo \"rvm --default use 3.2.3\" >> /opt/zammad/.bashrc"
  pct exec $CTID -- bash -c "echo \"source /usr/local/rvm/scripts/rvm\" >> /opt/zammad/.bashrc"

  # Installer Ruby 3.2.3
  msg_info "Installing Ruby 3.2.3"
  pct exec $CTID -- bash -c "usermod -a -G rvm zammad"
  pct exec $CTID -- bash -c "su - zammad -c \"rvm install ruby-3.2.3\""

  # Installer bundler, rake et rails
  msg_info "Installing bundler, rake and rails"
  pct exec $CTID -- bash -c "su - zammad -c \"rvm use ruby-3.2.3; gem install bundler rake rails\""

  # Installer les gems pour Zammad
  msg_info "Installing gems for Zammad"
  pct exec $CTID -- bash -c "su - zammad -c \"bundle config set without 'test development mysql'; bundle install\""

  # Créer la base de données PostgreSQL
  msg_info "Configuring PostgreSQL database"
  pct exec $CTID -- bash -c "sudo -u postgres createuser -s zammad" 
  pct exec $CTID -- bash -c "sudo -u postgres createdb -O zammad zammad"
  # Le script d'installation de Zammad vous demandera le mot de passe de l'utilisateur PostgreSQL "zammad". 
  # Assurez-vous de le noter, car vous en aurez besoin pour configurer Zammad.

  # Migrer la base de données et précompiler les assets
  msg_info "Migrating the database and precompiling assets"
  pct exec $CTID -- bash -c "cd /opt/zammad && RAILS_ENV=production bundle exec rake db:migrate"
  pct exec $CTID -- bash -c "cd /opt/zammad && RAILS_ENV=production bundle exec rake assets:precompile"

  # Configurer le serveur web Apache2
  msg_info "Configuring Apache2 web server"
  # Vous devrez configurer manuellement Apache2 pour servir Zammad.
  # Consultez la documentation de Zammad pour plus d'informations:
  # https://docs.zammad.org/en/latest/install/source.html#apache-configuration

  # Configuration du serveur de mail Postfix
  msg_info "Configuring Postfix mail server"
  pct exec $CTID -- bash -c "debconf-set-selections <<< 'postfix postfix/mailname string $HN'"
  pct exec $CTID -- bash -c "debconf-set-selections <<< 'postfix postfix/main_mailer_type string 'Internet Site''"
  pct exec $CTID -- bash -c "apt install -y postfix"
  # Vous devrez peut-être configurer davantage Postfix pour qu'il fonctionne correctement avec votre 
  # fournisseur de messagerie, par exemple pour configurer un relais SMTP si vous ne souhaitez pas 
  # envoyer les emails directement depuis le serveur.

  msg_ok "Zammad installed successfully"
}

function manage_zammad_services {
  msg_info "Managing Zammad services"
  # Zammad utilise des scripts init.d pour gérer ses services.
  # Vous pouvez les démarrer et les activer avec les commandes suivantes:
  pct exec $CTID -- bash -c "/etc/init.d/zammad start"
  pct exec $CTID -- bash -c "update-rc.d zammad defaults"
  msg_ok "Zammad services started"
}

function check_zammad_version {
  msg_info "Checking Zammad version"
  pct exec $CTID -- bash -c "cd /opt/zammad && zammad -v" # Correction ici
  msg_ok "Zammad version checked"
}

function motd_ssh_custom() {
  msg_info "Customizing MOTD"
  pct exec $CTID -- bash -c "echo 'Welcome to your Zammad LXC container!' > /etc/motd"
  msg_ok "MOTD customized"
}

header_info
start
build_container
install_zammad
manage_zammad_services  # Démarrer et activer les services Zammad
check_zammad_version   # Vérifier la version de Zammad
motd_ssh_custom
description

# Afficher l'URL pour accéder à Zammad
msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL:
         ${BL}http://${IP}/zammad${CL} \n"
