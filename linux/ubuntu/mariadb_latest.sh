#!/bin/bash

# Database
##########################################################
dbHost="localhost"
dbName="$DB_NAME"
dbUser="$DB_USER"
dbUserPassword="$DB_USER_PASSWORD"

dbPassword=`openssl rand -base64 12`
echo $dbPassword > /root/.pwd_mariadb


# Installing dependencies
##########################################################
sudo apt update
sudo apt install -y apt-transport-https
sudo apt install -y lsb-release ca-certificates software-properties-common curl
function download {
    url=$1
    filename=$2

    if [ -x "$(which wget)" ] ; then
        wget -q $url -O $2
    elif [ -x "$(which curl)" ]; then
        curl -o $2 -sfL $url
    else
        echo "Could not find curl or wget, please install one." >&2
    fi
}

download https://downloads.mariadb.com/MariaDB/mariadb_repo_setup  /tmp/mariadb_repo_setup
bash /tmp/mariadb_repo_setup
mariadbVersion=`awk -F'=' '$1 == "mariadb_server_version" {print $2}' /tmp/mariadb_repo_setup | cut -d'-' -f2`
#echo $mariadbVersion
export DEBIAN_FRONTEND="noninteractive"
sudo apt update
echo -e "\n############ INSTALLATION DE MARIADB ##################"

sudo debconf-set-selections <<< "maria-db-$mariadbVersion mysql-server/root_password password $dbPassword"
sudo debconf-set-selections <<< "maria-db-$mariadbVersion mysql-server/root_password_again password $dbPassword"
sudo apt-get install -qq mariadb-server

echo -e "\n############ CREATION DE L'UTILISATEUR MYSQL root ##################"

MYSQL=`which mysql`
Q1="use mysql;"
Q2="FLUSH PRIVILEGES;"
Q3="ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('$dbPassword');"

SQL="${Q1}${Q2}${Q3}"

$MYSQL -uroot -p$dbPassword -e "$SQL"

service mysql restart

echo -e "\n############ CREATION DE LA BASE $dbName ##################"
mysql -f -uroot -p$dbPassword -e "create database \`${dbName}\`;"
mysql -f -uroot -p$dbPassword -e "CREATE USER '$dbUser'@'localhost' IDENTIFIED BY '$dbUserPassword';"
mysql -f -uroot -p$dbPassword -e "GRANT ALL PRIVILEGES ON $dbName.* TO '$dbUser'@'%' IDENTIFIED BY '$dbUserPassword';FLUSH PRIVILEGES;"


echo -e "\n############ Changing the mysql bind-address ##############"
sudo sed -i "s/.*bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/my.cnf

sudo service mysql restart

