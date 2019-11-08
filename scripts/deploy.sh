#!/usr/bin/env bash
set -e
LOG_FILE=$HOME/deploy.log
MARIADB_PDNS_DBNAME=pdns
MARIADB_PDNS_USERNAME=pdns
IP_RANGE=91.226.31/24
SERVER_NAME=www.natalka1122.com
SSL_CERT_DIR=/etc/nginx/$SERVER_NAME
PDNS_API_PORT=8081
PHPINFO_PORT=80 ## One should open corresponding port on the firewall
PHPINFO_DIR=/var/www/html
TMP_DIR=/tmp

sudo mkdir -p $PHPINFO_DIR
sudo mkdir -p $TMP_DIR
sudo mkdir -p $SSL_CERT_DIR
echo ========== TASK 1/10 Update the system ==========
sudo apt update
sudo apt-get --yes upgrade
sudo apt-get --yes install net-tools pwgen

MARIADB_ROOT_PASSWORD=$(pwgen -s -1 14)
MARIADB_PDNS_PASSWORD=$(pwgen -s -1 14)
PDNS_API_PASSWORD=$(pwgen -s -1 14)
cp /etc/issue $LOG_FILE
echo Date script executed: $(date) >> $LOG_FILE
echo MariaDB password for root user: $MARIADB_ROOT_PASSWORD >>$LOG_FILE
echo PowerDNS user name: $MARIADB_PDNS_USERNAME >>$LOG_FILE
echo PowerDNS user password: $MARIADB_PDNS_PASSWORD >>$LOG_FILE
echo PowerDNS API password: $PDNS_API_PASSWORD >>$LOG_FILE
echo ========== TASK 2/10 Install MariaDB ==========
sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xF1656F24C74CD1D8
cat <<EOF >${TMP_DIR}/mariabd.list
# MariaDB 10.4 repository list - created 2019-11-07 16:57 UTC
# http://downloads.mariadb.org/mariadb/repositories/
deb [arch=amd64] http://mirror.timeweb.ru/mariadb/repo/10.4/debian buster main
deb-src http://mirror.timeweb.ru/mariadb/repo/10.4/debian buster main
EOF
sudo mv ${TMP_DIR}/mariabd.list /etc/apt/sources.list.d/
sudo apt update
sudo apt install --yes mariadb-server
sudo mysqladmin -u root password $MARIADB_ROOT_PASSWORD
echo ========== TASK 3/10 Install PowerDNS ==========
echo "deb [arch=amd64] http://repo.powerdns.com/debian buster-auth-master main" >${TMP_DIR}/powerdns.list
sudo mv ${TMP_DIR}/powerdns.list /etc/apt/sources.list.d/
cat <<EOF >${TMP_DIR}/pdns
Package: pdns-*
Pin: origin repo.powerdns.com
Pin-Priority: 600
EOF
sudo mv ${TMP_DIR}/pdns /etc/apt/preferences.d/
curl https://repo.powerdns.com/CBC8B383-pub.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get --yes install pdns-server pdns-backend-mysql
sudo sed 's/^launch=$/launch=gmysql/g' /etc/powerdns/pdns.conf >${TMP_DIR}/pdns.conf.template
cat <<EOF >>${TMP_DIR}/pdns.conf.template
gmysql-host=127.0.0.1
gmysql-user=${MARIADB_PDNS_USERNAME}
gmysql-dbname=${MARIADB_PDNS_DBNAME}
gmysql-password=${MARIADB_PDNS_PASSWORD}
api=yes
api-key=${PDNS_API_PASSWORD}
EOF
sudo mv ${TMP_DIR}/pdns.conf.template /etc/powerdns/pdns.conf
cat <<EOF >${TMP_DIR}/powerdns-init.sql
CREATE DATABASE ${MARIADB_PDNS_DBNAME};
CREATE USER '${MARIADB_PDNS_USERNAME}'@'localhost' IDENTIFIED BY '${MARIADB_PDNS_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MARIADB_PDNS_DBNAME}. * TO '${MARIADB_PDNS_USERNAME}'@'localhost';
USE ${MARIADB_PDNS_DBNAME};
EOF
curl https://raw.githubusercontent.com/PowerDNS/pdns/rel/auth-4.2.x/modules/gmysqlbackend/schema.mysql.sql >>${TMP_DIR}/powerdns-init.sql
mysql -u root -p$MARIADB_ROOT_PASSWORD < ${TMP_DIR}/powerdns-init.sql
echo ========== TASK 4/10 Install PowerDNS API ==========
echo Done early
echo ========== TASK 5/10 Check PowerDNS API ==========
sudo systemctl restart pdns
curl -k -v -H 'X-API-Key: ${PDNS_API_PASSWORD}' http://127.0.0.1:8081/api/v1/servers/localhost >>$LOG_FILE
echo ========== TASK 6/10 Install nginx ==========
sudo apt-get --yes install nginx
echo ====PROGRESS====== TASK 7/10 Proxy PowerDNS via nginx ==========
sudo openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=${SERVER_NAME}"  -keyout ${SSL_CERT_DIR}/cert.key -out ${SSL_CERT_DIR}/cert.crt
cat <<EOF >${TMP_DIR}/nginx-ssl.conf
server {
    listen 443;
    allow ${IP_RANGE};
    deny all;
    server_name ${SERVER_NAME};
    ssl_certificate           ${SSL_CERT_DIR}/cert.crt;
    ssl_certificate_key       ${SSL_CERT_DIR}/cert.key;
    ssl on;
    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;
    access_log            /var/log/nginx/${SERVER_NAME}.access.log;
    location / {
        proxy_set_header        Host \$host;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_pass          http://localhost:${PDNS_API_PORT};
        proxy_read_timeout  90;
        proxy_redirect      http://localhost:${PDNS_API_PORT} https://${SERVER_NAME};
    }
}
EOF
sudo cp ${TMP_DIR}/nginx-ssl.conf /etc/nginx/sites-available
sudo ln -s /etc/nginx/sites-available/nginx-ssl.conf /etc/nginx/sites-enabled/
sudo systemctl restart nginx
echo ========== TASK 8/10 Check API access from Internet ==========
echo ========== TASK 9/10 Limit allowed IP addresses ==========
echo ========== TASK 10/10 Check API access from Internet ==========
echo ========== TASK 11/10 Install php-fpm ==========
sudo apt --yes install php-fpm
echo ========== TASK 12/10 Create phpinfo\(\)\; site ==========
sudo echo "<?php phpinfo(); ?>" > ${TMP_DIR}/index.php
sudo mv ${TMP_DIR}/index.php $PHPINFO_DIR
cat <<EOF >${TMP_DIR}/nginx-phpinfo.conf
server {
    listen ${PHPINFO_PORT};

    root ${PHPINFO_DIR};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.3-fpm.sock;
    }
}
EOF
sudo mv ${TMP_DIR}/nginx-phpinfo.conf /etc/nginx/sites-available
sudo ln -s /etc/nginx/sites-available/nginx-phpinfo.conf /etc/nginx/sites-enabled/
if [ $PHPINFO_PORT -eq 80 ]
then
    sudo rm /etc/nginx/sites-enabled/default
fi
sudo systemctl restart nginx