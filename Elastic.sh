#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)

function header_info {
  clear
  cat <<"EOF"

_________        .__  .__                
\_   ___ \___.__.|  | |__| ____   ____  
/    \  \<   |  ||  | |  |/    \ / ___\ 
\     \___\___  ||  |_|  |   |  / /_/  >
 \______  / ____||____/__|___|  \___  / 
        \/\/                  \/_____/  

EOF
}

APP="Elasticsearch & Kibana"
var_disk="30"
var_cpu="8"
var_ram="16384" # 16 Go
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
  msg_info "Installation des dépendances système"
  pct exec "$CTID" -- bash -c "apt update && apt upgrade -y"
  pct exec "$CTID" -- bash -c "apt install -y apt-transport-https curl openjdk-17-jre-headless unzip"
  msg_ok "Dépendances système installées"
}

function install_elasticsearch() {
  msg_info "Installation d'Elasticsearch"
  pct exec "$CTID" -- bash -c "wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -"
  pct exec "$CTID" -- bash -c "echo 'deb https://artifacts.elastic.co/packages/8.x/apt stable main' > /etc/apt/sources.list.d/elastic-8.x.list"
  pct exec "$CTID" -- bash -c "apt update && apt install -y elasticsearch"
  pct exec "$CTID" -- bash -c "systemctl enable elasticsearch --now"
  msg_ok "Elasticsearch installé et démarré"
}

function configure_memory() {
  msg_info "Configuration de la mémoire pour Elasticsearch"
  
  pct exec "$CTID" -- bash -c "sed -i 's/^-Xms.*/-Xms8g/' /etc/elasticsearch/jvm.options"
  pct exec "$CTID" -- bash -c "sed -i 's/^-Xmx.*/-Xmx8g/' /etc/elasticsearch/jvm.options"

  pct exec "$CTID" -- systemctl restart elasticsearch
  msg_ok "Mémoire configurée pour Elasticsearch (8 Go)"
}

function configure_ssl() {
  msg_info "Configuration des certificats SSL"
  
  # Création des certificats CA
  pct exec "$CTID" -- bash -c "/usr/share/elasticsearch/bin/elasticsearch-certutil ca --silent --pem --out /etc/elasticsearch/certs/ca.zip"
  pct exec "$CTID" -- bash -c "unzip -o /etc/elasticsearch/certs/ca.zip -d /etc/elasticsearch/certs/"
  
  # Création des certificats pour Elasticsearch et Kibana
  pct exec "$CTID" -- bash -c "/usr/share/elasticsearch/bin/elasticsearch-certutil cert --pem --ca-cert /etc/elasticsearch/certs/ca/ca.crt --ca-key /etc/elasticsearch/certs/ca/ca.key --out /etc/elasticsearch/certs/instance.zip --silent"
  pct exec "$CTID" -- bash -c "unzip -o /etc/elasticsearch/certs/instance.zip -d /etc/elasticsearch/certs/"
  
  # Permissions des certificats
  pct exec "$CTID" -- bash -c "chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs/"
  pct exec "$CTID" -- bash -c "chmod -R 600 /etc/elasticsearch/certs/"
  
  pct exec "$CTID" -- bash -c "cp /etc/elasticsearch/certs/ca/ca.crt /etc/kibana/certs/http_ca.crt"

  msg_ok "Certificats SSL configurés"
}

function configure_elasticsearch() {
  msg_info "Configuration d'Elasticsearch"
  pct exec "$CTID" -- bash -c "echo 'xpack.security.enabled: true
xpack.security.http.ssl:
  enabled: true
  certificate: /etc/elasticsearch/certs/localhost/localhost.crt
  key: /etc/elasticsearch/certs/localhost/localhost.key
xpack.security.transport.ssl:
  enabled: true
  verification_mode: certificate
  certificate_authorities: [\"/etc/elasticsearch/certs/ca/ca.crt\"]
' >> /etc/elasticsearch/elasticsearch.yml"
  pct exec "$CTID" -- systemctl restart elasticsearch
  msg_ok "Elasticsearch configuré"
}

function generate_kibana_token() {
  msg_info "Génération du token pour Kibana"
  TOKEN=$(pct exec "$CTID" -- bash -c "/usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-server")
  if [ $? -ne 0 ]; then
    msg_error "Échec de la génération du token pour Kibana"
    exit 1
  fi
  echo -e "Token pour Kibana : \e[92m$TOKEN\e[39m"
  msg_ok "Token généré pour Kibana"
}

function install_kibana() {
  msg_info "Installation de Kibana"
  pct exec "$CTID" -- bash -c "apt install -y kibana"
  pct exec "$CTID" -- bash -c "systemctl enable kibana --now"
  msg_ok "Kibana installé et démarré"
}

function configure_kibana() {
  msg_info "Configuration de Kibana"
  pct exec "$CTID" -- bash -c "echo 'server.ssl.enabled: true
server.ssl.certificate: /etc/elasticsearch/certs/localhost/localhost.crt
server.ssl.key: /etc/elasticsearch/certs/localhost/localhost.key
elasticsearch.hosts: [\"https://localhost:9200\"]
elasticsearch.ssl.certificateAuthorities: [\"/etc/kibana/certs/http_ca.crt\"]
' >> /etc/kibana/kibana.yml"
  pct exec "$CTID" -- systemctl restart kibana
  msg_ok "Kibana configuré"
}

function retrieve_elastic_password() {
  msg_info "Récupération du mot de passe Elasticsearch"
  PASSWORD=$(pct exec "$CTID" -- bash -c "grep -m 1 'elastic' /etc/elasticsearch/elasticsearch.keystore | awk '{print \$NF}'")
  if [ -z "$PASSWORD" ]; then
    msg_error "Impossible de récupérer le mot de passe utilisateur elastic."
  else
    echo -e "Mot de passe utilisateur elastic : \e[92m$PASSWORD\e[39m"
  fi
  msg_ok "Mot de passe récupéré"
}

function main() {
  install_dependencies
  install_elasticsearch
  configure_memory
  configure_ssl
  configure_elasticsearch
  install_kibana
  configure_kibana
  generate_kibana_token
  retrieve_elastic_password
}

header_info
start
build_container
main
description

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Installation d'Elasticsearch et Kibana terminée!"
echo -e "Accédez à Kibana à l'adresse : https://$IP:5601"
