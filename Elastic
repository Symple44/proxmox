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
var_cpu="4"
var_ram="8192"
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

function install_kibana() {
  msg_info "Installation de Kibana"
  pct exec "$CTID" -- bash -c "apt install -y kibana"
  pct exec "$CTID" -- bash -c "systemctl enable kibana --now"
  msg_ok "Kibana installé et démarré"
}

function configure_ssl() {
  msg_info "Configuration des certificats SSL"
  pct exec "$CTID" -- bash -c "/usr/share/elasticsearch/bin/elasticsearch-certutil ca --silent --pem --out /etc/elasticsearch/certs/ca.zip"
  pct exec "$CTID" -- bash -c "unzip -o /etc/elasticsearch/certs/ca.zip -d /etc/elasticsearch/certs/"
  
  pct exec "$CTID" -- bash -c "/usr/share/elasticsearch/bin/elasticsearch-certutil cert --pem --ca-cert /etc/elasticsearch/certs/ca/ca.crt --ca-key /etc/elasticsearch/certs/ca/ca.key --out /etc/elasticsearch/certs/instance.zip --silent"
  pct exec "$CTID" -- bash -c "unzip -o /etc/elasticsearch/certs/instance.zip -d /etc/elasticsearch/certs/"

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

function main() {
  install_dependencies
  install_elasticsearch
  install_kibana
  configure_ssl
  configure_elasticsearch
  configure_kibana
}

header_info
start
build_container
main
description

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Installation d'Elasticsearch et Kibana terminée!"
echo -e "Accédez à Kibana à l'adresse : https://$IP:5601"
