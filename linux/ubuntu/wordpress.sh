#!/bin/bash

# Database
##########################################################
dbHost="localhost"
dbName="$DB_NAME"
dbUser="$DB_USER"
dbUserPassword="$DB_USER_PASSWORD"
#dbroot password
dbPassword=`openssl rand -base64 12`
echo $dbPassword > /root/.pwd_mariadb
WP_DIR="wordpress"

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

echo -e "\n####################### Install APACHE2 PHP7.4 (ubuntu | debian)###################"
sudo apt-get install -y apache2

. /tmp/mariadb_repo_setup
os_type=""
os_version=""
identify_os

if [ "$os_type" = "ubuntu" ];then
	sudo add-apt-repository ppa:ondrej/php -y
elif  [ "$os_type" = "debian" ];then
	sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
	echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
fi
sudo apt update
sudo apt install -y php7.4 libapache2-mod-php7.4 php7.4-{mysql,curl,gd,mbstring,mcrypt,xml,xmlrpc}
#sudo apt-get -y install php7.2 libapache2-mod-php7.2 php7.2-{mysql,common,gd,json,curl,mbstring,cli,xml,imap,ldap,xmlrpc,zip,bcmath,intl}

##########################
# install phpmyadmin
##########################
if [ ! -f /etc/phpmyadmin/config.inc.php ];
then

	# Used debconf-get-selections to find out what questions will be asked
	# This command needs debconf-utils

	# Handy for debugging. clear answers phpmyadmin: echo PURGE | debconf-communicate phpmyadmin

	echo 'phpmyadmin phpmyadmin/dbconfig-install boolean false' | debconf-set-selections
	echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | debconf-set-selections

	echo 'phpmyadmin phpmyadmin/app-password-confirm password $dbPassword' | debconf-set-selections
	echo 'phpmyadmin phpmyadmin/mysql/admin-pass password $dbPassword' | debconf-set-selections
	echo 'phpmyadmin phpmyadmin/password-confirm password $dbPassword' | debconf-set-selections
	echo 'phpmyadmin phpmyadmin/setup-password password $dbPassword' | debconf-set-selections
	echo 'phpmyadmin phpmyadmin/database-type select mysql' | debconf-set-selections
	echo 'phpmyadmin phpmyadmin/mysql/app-pass password $dbPassword' | debconf-set-selections

	echo 'dbconfig-common dbconfig-common/mysql/app-pass password $dbPassword' | debconf-set-selections
	#echo 'dbconfig-common dbconfig-common/mysql/app-pass password' | debconf-set-selections
	echo 'dbconfig-common dbconfig-common/password-confirm password $dbPassword' | debconf-set-selections
	echo 'dbconfig-common dbconfig-common/app-password-confirm password $dbPassword' | debconf-set-selections
	echo 'dbconfig-common dbconfig-common/app-password-confirm password $dbPassword' | debconf-set-selections
	echo 'dbconfig-common dbconfig-common/password-confirm password $dbPassword' | debconf-set-selections

	apt-get -y install phpmyadmin
fi

########################################
# Install Wordpress
########################################
cat > /etc/apache2/sites-available/wordpress.conf <<WPCONF

<virtualhost *:80>
  DocumentRoot /var/www/${WP_DIR}

  <Location />
    Options -Indexes
  </Location>

  ErrorLog \${APACHE_LOG_DIR}/wordpress_error.log
  LogLevel warn
  CustomLog \${APACHE_LOG_DIR}/wordpress_access.log haproxy_combined
</virtualhost>
WPCONF

sudo a2enmod php7.4
sudo a2ensite wordpress
sudo a2enmod rewrite
sudo a2dissite default
sudo a2dissite 000-default
sudo service apache2 restart

#########################################

cd /var/tmp
wget -q https://wordpress.org/latest.tar.gz
mkdir -p /var/www/${WP_DIR}
#tar xf /var/tmp/latest.tar.gz -C /var/www
tar xf /var/tmp/latest.tar.gz
mv wordpress/* /var/www/${WP_DIR}
rm -r wordpress/
chown -R www-data:www-data /var/www/${WP_DIR}

cd /var/www/${WP_DIR}
cp -p wp-config-sample.php wp-config.php
sed -i "s/define( *'DB_NAME'.*/define('DB_NAME', '$dbName');/" wp-config.php
sed -i "s/define( *'DB_USER'.*/define('DB_USER', '$dbUser');/" wp-config.php
sed -i "s/define( *'DB_PASSWORD'.*/define('DB_PASSWORD', '$dbUserPassword');/" wp-config.php
sed -i "s/define( *'DB_HOST'.*/define('DB_HOST', '$dbHost');/" wp-config.php