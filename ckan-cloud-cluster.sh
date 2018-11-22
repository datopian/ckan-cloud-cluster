#!/usr/bin/env bash

info() {
    echo '('$(hostname)'):' $@
}

great_success() {
    info Great Success! $@
}

error() {
    info Error! $@
}

warning() {
    info Warning! $@
}

server_side() {
    [ -e /etc/ckan-cloud-cluster/version ]
}

client_side() {
    ! server_side
}

install_nginx_ssl() {
    ! server_side && return 1
    info Installing Nginx and Certbot with strong SSL security &&\
    apt update -y &&\
    apt install -y nginx software-properties-common &&\
    add-apt-repository universe &&\
    add-apt-repository ppa:certbot/certbot &&\
    apt-get update &&\
    apt-get install -y python-certbot-nginx &&\
    if [ -e /etc/ssl/certs/dhparam.pem ]; then warning Ephemeral Diffie-Hellman key already exists at /etc/ssl/certs/dhparam.pem - delete to recreate
    else info Generating Ephemeral Diffie-Hellman key && openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048; fi &&\
    mkdir -p /var/lib/letsencrypt/.well-known &&\
    chgrp www-data /var/lib/letsencrypt &&\
    chmod g+s /var/lib/letsencrypt &&\
    info Saving /etc/nginx/snippets/letsencrypt.conf &&\
    echo 'location ^~ /.well-known/acme-challenge/ {
  allow all;
  root /var/lib/letsencrypt/;
  default_type "text/plain";
  try_files $uri =404;
}' | tee /etc/nginx/snippets/letsencrypt.conf &&\
    info Saving /etc/nginx/snippets/ssl.conf &&\
    echo 'ssl_dhparam /etc/ssl/certs/dhparam.pem;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
# recommended cipher suite for modern browsers
ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
# cipher suite for backwards compatibility (IE6/windows XP)
# ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
ssl_prefer_server_ciphers on;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 30s;
add_header Strict-Transport-Security "max-age=15768000; includeSubdomains; preload";
add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;' | tee /etc/nginx/snippets/ssl.conf &&\
    info Saving /etc/nginx/snippets/http2_proxy.conf &&\
    echo 'proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Port $server_port;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_read_timeout 900s;' | tee /etc/nginx/snippets/http2_proxy.conf &&\
info Clearing existing Nginx sites from /etc/nginx/sites-enabled &&\
rm -f /etc/nginx/sites-enabled/* &&\
info Saving /etc/nginx/sites-enabled/default &&\
echo '
map $http_upgrade $connection_upgrade {
    default Upgrade;
    '"''"'      close;
}
server {
  listen 80;
  server_name _;
  include snippets/letsencrypt.conf;
  location / {
      return 200 '"'it works!'"';
      add_header Content-Type text/plain;
  }
}' | tee /etc/nginx/sites-enabled/default &&\
    info Verifying certbot renewal systemd timer &&\
    systemctl list-timers | grep certbot &&\
    cat /lib/systemd/system/certbot.timer &&\
    info Restarting Nginx &&\
    systemctl restart nginx
    [ "$?" != "0" ] && error Failed to install strong security Nginx and Certbot && return 1
    great_success && return 0
}

setup_ssl() {
    ! server_side && return 1
    local LETSENCRYPT_EMAIL="${1}"
    local CERTBOT_DOMAINS="${2}"
    local LETSENCRYPT_DOMAIN="${3}"
    ( [ -z "${LETSENCRYPT_EMAIL}" ] || [ -z "${CERTBOT_DOMAINS}" ] || [ -z "${LETSENCRYPT_DOMAIN}" ] ) \
        && error missing required arguments && return 1
    info Setting up SSL &&\
    info LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL} CERTBOT_DOMAINS=${CERTBOT_DOMAINS} LETSENCRYPT_DOMAIN=${LETSENCRYPT_DOMAIN} &&\
    certbot certonly --agree-tos --email ${LETSENCRYPT_EMAIL} --webroot -w /var/lib/letsencrypt/ -d ${CERTBOT_DOMAINS} &&\
    echo "ssl_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/privkey.pem;
ssl_trusted_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/chain.pem;" \
    | tee /etc/nginx/snippets/letsencrypt_certs.conf &&\
    echo "${LETSENCRYPT_EMAIL}" > /etc/ckan-cloud-cluster/LETSENCRYPT_EMAIL &&\
    echo "${LETSENCRYPT_DOMAIN}" > /etc/ckan-cloud-cluster/LETSENCRYPT_DOMAIN &&\
    echo "${CERTBOT_DOMAINS}" > /etc/ckan-cloud-cluster/CERTBOT_DOMAINS &&\
    [ "$?" != "0" ] && error Failed to setup SSL && return 1
    sudo systemctl restart nginx
    great_success && return 0
}

add_certbot_domain() {
    ! server_side && return 1
    ( ! [ -e /etc/ckan-cloud-cluster/LETSENCRYPT_EMAIL ] || ! [ -e /etc/ckan-cloud-cluster/LETSENCRYPT_DOMAIN ] || ! [ -e /etc/ckan-cloud-cluster/CERTBOT_DOMAINS ] ) \
        && error Must setup SSL before adding domains && return 1
    local LETSENCRYPT_EMAIL=`cat /etc/ckan-cloud-cluster/LETSENCRYPT_EMAIL`
    local LETSENCRYPT_DOMAIN=`cat /etc/ckan-cloud-cluster/LETSENCRYPT_DOMAIN`
    local CERTBOT_DOMAINS=`cat /etc/ckan-cloud-cluster/CERTBOT_DOMAINS`
    local DOMAIN="${1}"
    echo "${CERTBOT_DOMAINS}" | grep ${DOMAIN} && error Domain ${DOMAIN} already included in CERTBOT_DOMAINS && return 1
    CERTBOT_DOMAINS="${CERTBOT_DOMAINS},${DOMAIN}"
    ! setup_ssl ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAIN} && return 1
    return 0
}

add_nginx_site() {
    ! server_side && return 1
    local SERVER_NAME="${1}"
    local SITE_NAME="${2}"
    local NGINX_CONFIG_SNIPPET="${3}"
    ( [ -z "${SERVER_NAME}" ] || [ -z "${SITE_NAME}" ] || [ -z "${NGINX_CONFIG_SNIPPET}" ] ) \
        && error missing required arguments && return 1
    info Adding nginx Site &&\
    info SERVER_NAME=${SERVER_NAME} SITE_NAME=${SITE_NAME} NGINX_CONFIG_SNIPPET=${NGINX_CONFIG_SNIPPET} &&\
    info Saving /etc/nginx/sites-enabled/${SITE_NAME} &&\
    echo 'server {
  listen 80;
  listen    [::]:80;
  server_name '${SERVER_NAME}';
  include snippets/letsencrypt.conf;
  return 301 https://$host$request_uri;
}
server {
  listen 443 ssl spdy;
  server_name '${SERVER_NAME}';
  include snippets/letsencrypt_certs.conf;
  include snippets/ssl.conf;
  include snippets/letsencrypt.conf;
  include snippets/'${NGINX_CONFIG_SNIPPET}'.conf;
}' | tee /etc/nginx/sites-enabled/${SITE_NAME} &&\
    info Restarting Nginx &&\
    systemctl restart nginx
    [ "$?" != "0" ] && error Failed to add Nginx site && return 1
    great_success && return 0
}

add_nginx_site_http2_proxy() {
    ! server_side && return 1
    local SERVER_NAME="${1}"
    local SITE_NAME="${2}"
    local NGINX_CONFIG_SNIPPET="${3}"
    local PROXY_PASS_PORT="${4}"
    ( [ -z "${SERVER_NAME}" ] || [ -z "${SITE_NAME}" ] || [ -z "${NGINX_CONFIG_SNIPPET}" ] || [ -z "${PROXY_PASS_PORT}" ] ) \
        && error missing required arguments && return 1
    info Saving /etc/nginx/snippets/${NGINX_CONFIG_SNIPPET}.conf &&\
    echo "location / {
  proxy_pass http://localhost:${PROXY_PASS_PORT};
  include snippets/http2_proxy.conf;
}" | sudo tee /etc/nginx/snippets/${NGINX_CONFIG_SNIPPET}.conf &&\
    add_nginx_site "${SERVER_NAME}" "${SITE_NAME}" "${NGINX_CONFIG_SNIPPET}"
}

init() {
    ! client_side && return 1
    ! local ACTIVE_DOCKER_MACHINE=`docker-machine active` && return 1
    local CKAN_CLOUD_CLUSTER_VERSION="${1}"
    info Initializing Docker Machine ${ACTIVE_DOCKER_MACHINE} with ckan-cloud-cluster v${CKAN_CLOUD_CLUSTER_VERSION} &&\
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'bash -c "
            sudo mkdir -p /usr/local/src/ckan-cloud-cluster &&\
            sudo chown -R $USER /usr/local/src/ckan-cloud-cluster
        "'
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'sudo bash -c "
            TEMPDIR=`mktemp -d` && cd /$TEMPDIR &&\
            wget -q https://github.com/ViderumGlobal/ckan-cloud-cluster/archive/v'${CKAN_CLOUD_CLUSTER_VERSION}'.tar.gz &&\
            tar -xzf 'v${CKAN_CLOUD_CLUSTER_VERSION}'.tar.gz &&\
            cp -rf ckan-cloud-cluster-'${CKAN_CLOUD_CLUSTER_VERSION}'/* /usr/local/src/ckan-cloud-cluster/ &&\
            cp -f /usr/local/src/ckan-cloud-cluster/ckan-cloud-cluster.sh /usr/local/bin/ckan-cloud-cluster &&\
            chmod +x /usr/local/bin/ckan-cloud-cluster &&\
            mkdir -p /etc/ckan-cloud-cluster && echo '${CKAN_CLOUD_CLUSTER_VERSION}' > /etc/ckan-cloud-cluster/version
        "'
    [ "$?" != "0" ] && error Failed to initialize ckan-cloud-cluster && return 1
    great_success && return 0
}

init_dev() {
    ! client_side && return 1
    ! local ACTIVE_DOCKER_MACHINE=`docker-machine active` && return 1
    ! [ -e ./ckan-cloud-cluster.sh ] && error init_dev must run from ckan-cloud-cluster project directory && return 1
    info Syncing local directory to Docker Machine ${ACTIVE_DOCKER_MACHINE} &&\
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'bash -c "
            sudo mkdir -p /usr/local/src/ckan-cloud-cluster &&\
            sudo chown -R $USER /usr/local/src/ckan-cloud-cluster
        "'
    docker-machine scp -q -d -r . ${ACTIVE_DOCKER_MACHINE}:/usr/local/src/ckan-cloud-cluster/ &&\
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'sudo bash -c "
            cp -f /usr/local/src/ckan-cloud-cluster/ckan-cloud-cluster.sh /usr/local/bin/ckan-cloud-cluster &&\
            chmod +x /usr/local/bin/ckan-cloud-cluster &&\
            mkdir -p /etc/ckan-cloud-cluster && echo '0.0.0' > /etc/ckan-cloud-cluster/version
        "'
    [ "$?" != "0" ] && error Failed to initialize ckan-cloud-cluster && return 1
    great_success && return 0
}

init_ckan_cloud_docker_dev() {
    ! client_side && return 1
    ! local ACTIVE_DOCKER_MACHINE=`docker-machine active` && return 1
    CKAN_CLOUD_DOCKER_DIR="${1}"
    [ -z "${CKAN_CLOUD_DOCKER_DIR}" ] && error missing required args && return 1
    ! [ -e "${CKAN_CLOUD_DOCKER_DIR}/jenkins/scripts/create_instance.sh" ] && error invalid ckan-cloud-docker directory && return 1
    info Syncing ckan-cloud-docker local directory ${CKAN_CLOUD_DOCKER_DIR} to Docker Machine ${ACTIVE_DOCKER_MACHINE} &&\
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'bash -c "
            sudo mkdir -p /etc/ckan-cloud/ckan-cloud-docker &&\
            sudo chown -R 1000:1000 /etc/ckan-cloud
        "' &&\
    docker-machine scp -q -d -r ${CKAN_CLOUD_DOCKER_DIR}/ ${ACTIVE_DOCKER_MACHINE}:/etc/ckan-cloud/ckan-cloud-docker/ >/dev/null 2>&1
    [ "$?" != "0" ] && error Failed to initialize dev version of ckan-cloud-docker && return 1
    great_success && return 0
}

get_aws_public_hostname() {
    ! server_side && return 1
    ! curl -s http://169.254.169.254/latest/meta-data/public-hostname && return 1
    echo
}

start_rancher() {
    ! server_side && return 1
    SERVER_NAME="${1}"
    [ -z "${SERVER_NAME}" ] && error missing required args && return 1
    docker rm -f rancher >/dev/null 2>&1
    mkdir -p /var/lib/rancher &&\
    docker run -d --name rancher --restart unless-stopped -p 8000:80 \
               -v "/var/lib/rancher:/var/lib/rancher" rancher/rancher:stable
    [ "$?" != "0" ] && error Failed to start Rancher && return 1
    SITE_NAME=rancher
    NGINX_CONFIG_SNIPPET=rancher
    PROXY_PASS_PORT=8000
    add_nginx_site_http2_proxy ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET} ${PROXY_PASS_PORT}
}

start_jenkins() {
    ! server_side && return 1
    SERVER_NAME="${1}"
    JENKINS_IMAGE="${2}"
    ( [ -z "${SERVER_NAME}" ] || [ -z "${JENKINS_IMAGE}" ] ) && error missing required args && return 1
    docker rm -f jenkins >/dev/null 2>&1
    mkdir -p /var/jenkins_home &&\
    chown -R 1000:1000 /var/jenkins_home &&\
    docker run -d --name jenkins -p 8080:8080 \
               -v /var/jenkins_home:/var/jenkins_home \
               -v /etc/ckan-cloud:/etc/ckan-cloud \
               -v /var/run/docker.sock:/var/run/docker.sock \
               ${JENKINS_IMAGE}
    [ "$?" != "0" ] && error Failed to start Jenkins && return 1
    SITE_NAME=jenkins
    NGINX_CONFIG_SNIPPET=jenkins
    PROXY_PASS_PORT=8080
    add_nginx_site_http2_proxy ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET} ${PROXY_PASS_PORT}
}

start_cca_operator_server() {
    ! server_side && return 1
    docker rm -f cca-operator-server >/dev/null 2>&1
    source /etc/ckan-cloud/.cca_operator-secrets.env &&\
    source /etc/ckan-cloud/.cca_operator-image.env &&\
    info Starting cca-operator server "(${CCA_OPERATOR_IMAGE})" &&\
    docker run -d --name cca-operator-server -p 8022:22 \
               -v /etc/ckan-cloud:/etc/ckan-cloud \
               -e KUBECONFIG=/etc/ckan-cloud/.kube-config \
               -e CF_AUTH_EMAIL=${CF_AUTH_EMAIL} -e CF_AUTH_KEY=${CF_AUTH_KEY} -e CF_ZONE_NAME=${CF_ZONE_NAME} \
               ${CCA_OPERATOR_IMAGE} ./server.sh
    [ "$?" != "0" ] && error Failed to start cca-operator server && return 1
    great_success && return 0
}

init_ckan_cloud() {
    ! server_side && return 1
    CKAN_CLOUD_DOCKER_VERSION="${1}"
    [ -z "${CKAN_CLOUD_DOCKER_VERSION}" ] && error missing required args && return 1
    info Downloading ckan-cloud-docker v${CKAN_CLOUD_DOCKER_VERSION} &&\
    mkdir -p /etc/ckan-cloud/ckan-cloud-docker &&\
    chown -R 1000:1000 /etc/ckan-cloud &&\
    wget -q https://github.com/ViderumGlobal/ckan-cloud-docker/archive/v${CKAN_CLOUD_DOCKER_VERSION}.tar.gz &&\
    tar -xzf v${CKAN_CLOUD_DOCKER_VERSION}.tar.gz &&\
    cp -rf ckan-cloud-docker-${CKAN_CLOUD_DOCKER_VERSION}/* /etc/ckan-cloud/ckan-cloud-docker &&\
    rm -rf ckan-cloud-docker-${CKAN_CLOUD_DOCKER_VERSION} && rm v${CKAN_CLOUD_DOCKER_VERSION}.tar.gz
    [ "$?" != "0" ] && error Failed download ckan-cloud-docker && return 1
    info Copying the preconfigured Jenkins job configurations &&\
    mkdir -p /var/jenkins_home/jobs &&\
    cp -rf /etc/ckan-cloud/ckan-cloud-docker/jenkins/jobs/* /var/jenkins_home/jobs/ &&\
    chown -R 1000:1000 /var/jenkins_home
    [ "$?" != "0" ] && error Failed to copy the Jenkins job configurations && return 1
    great_success && return 0
}

init_cca_operator() {
    ! server_side && return 1
    echo '#!/usr/bin/env bash
    source /etc/ckan-cloud/.cca_operator-secrets.env
    source /etc/ckan-cloud/.cca_operator-image.env
    if [ "${QUIET}" == "1" ]; then
        sudo docker run ${CCA_OPERATOR_DOCKER_RUN_ARGS:--i} --rm \
            -v /etc/ckan-cloud:/etc/ckan-cloud \
            -e KUBECONFIG=/etc/ckan-cloud/.kube-config \
            -e CF_AUTH_EMAIL=${CF_AUTH_EMAIL} -e CF_AUTH_KEY=${CF_AUTH_KEY} -e CF_ZONE_NAME=${CF_ZONE_NAME} \
            ${CCA_OPERATOR_IMAGE} 2>/dev/null "$@"
    else
        sudo docker run ${CCA_OPERATOR_DOCKER_RUN_ARGS:--i} --rm \
            -v /etc/ckan-cloud:/etc/ckan-cloud \
            -e KUBECONFIG=/etc/ckan-cloud/.kube-config \
            -e CF_AUTH_EMAIL=${CF_AUTH_EMAIL} -e CF_AUTH_KEY=${CF_AUTH_KEY} -e CF_ZONE_NAME=${CF_ZONE_NAME} \
            ${CCA_OPERATOR_IMAGE} "$@"
    fi' > /etc/ckan-cloud/cca_operator.sh &&\
    echo '#!/usr/bin/env bash
    CCA_OPERATOR_DOCKER_RUN_ARGS="-it" /etc/ckan-cloud/cca_operator.sh --' > /etc/ckan-cloud/cca_operator_shell.sh &&\
    chmod +x /etc/ckan-cloud/*.sh && chown -R 1000:1000 /etc/ckan-cloud
    [ "$?" != "0" ] && error Failed to initialize cca-operator && return 1
    great_success && return 0
}

install_helm() {
    ! server_side && return 1
    /etc/ckan-cloud/cca_operator.sh -c "
        kubectl --namespace kube-system create serviceaccount tiller;
        kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller;
        helm init --service-account tiller --history-max 2 --upgrade --wait &&\
        helm version
    "
    [ "$?" != "0" ] && error Failed to install Helm && return 1
    /etc/ckan-cloud/cca_operator.sh -c "
        kubectl -n kube-system delete service tiller-deploy;
        kubectl -n kube-system patch deployment tiller-deploy --patch 'spec:
  template:
    spec:
      containers:
        - name: tiller
          ports: []
          command: [\"/tiller\"]
          args: [\"--listen=localhost:44134\"]'
    "
    [ "$?" != "0" ] && error Failed to limit Helm access && return 1
    great_success && return 0
}

upgrade() {
    ! client_side && return 1
    CKAN_CLOUD_CLUSTER_VERSION="${1}"
    CKAN_CLOUD_DOCKER_VERSION="${2}"
    ( [ -z "${CKAN_CLOUD_CLUSTER_VERSION}" ] || [ -z "${CKAN_CLOUD_DOCKER_VERSION}" ] ) && error missing required args && return 1
    info Upgrading ckan-cloud-cluster to v${CKAN_CLOUD_CLUSTER_VERSION} &&\
    init $CKAN_CLOUD_CLUSTER_VERSION &&\
    docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster init_ckan_cloud ${CKAN_CLOUD_DOCKER_VERSION}
    [ "$?" != "0" ] && error Failed to upgrade CKAN Cloud && return 1
    great_success && return 0
}

eval "$@"
