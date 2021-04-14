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
Joomla_DIR="joomla"
JoomlaVersion="3-9-25"

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
#echo $os_type
#echo $os_version

if [ "$os_type" = "ubuntu" ];then
	sudo add-apt-repository ppa:ondrej/php -y
elif  [ "$os_type" = "debian" ];then
	sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
	echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
fi

sudo apt-get update
sudo apt -y install php7.4 libapache2-mod-php7.4 php7.4-{common,mbstring,xmlrpc,soap,gd,xml,intl,mysql,cli,mcrypt,ldap,zip,curl}

sed -i "s/max_execution_time.*/max_execution_time = 360/" /etc/php/7.4/apache2/php.ini
sed -i "s/file_uploads.*/file_uploads = On/" /etc/php/7.4/apache2/php.ini
sed -i "s/memory_limit.*/memory_limit = 256M/" /etc/php/7.4/apache2/php.ini
sed -i "s/upload_max_filesize.*/upload_max_filesize = 64M/" /etc/php/7.4/apache2/php.ini
sed -i "s/post_max_size.*/post_max_size = 10M/"  /etc/php/7.4/apache2/php.ini
sed -i "s/allow_url_fopen.*/allow_url_fopen = On/"  /etc/php/7.4/apache2/php.ini
sed -i "s/;date.timezone.*/date.timezone= Europe\/Paris/"  /etc/php/7.4/apache2/php.ini


echo -e "\n############ INSTALLATION DE COMPOSER ##################"
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/bin --filename=composer
export COMPOSER_HOME="$HOME/.config/composer";



########################################
# Install joomla
########################################
cat > /etc/apache2/sites-available/joomla.conf <<WPCONF

<virtualhost *:80>
  DocumentRoot /var/www/${Joomla_DIR}

  <Location />
    Options -Indexes
  </Location>

  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined

	<Directory /var/www/${Joomla_DIR}>
		Options +FollowSymlinks
        AllowOverride All
        Require all granted
     </Directory>


</virtualhost>
WPCONF
sudo a2ensite joomla

sudo a2enmod rewrite
sudo a2enmod php7.4

sudo a2dissite default
sudo a2dissite 000-default

sudo service apache2 restart

#########################################

cd /tmp && wget https://downloads.joomla.org/fr/cms/joomla3/$JoomlaVersion/Joomla_$JoomlaVersion-Stable-Full_Package.tar.gz
mkdir -p /var/www/${Joomla_DIR}
tar -zxvf Joomla_$JoomlaVersion-Stable-Full_Package.tar.gz -C /var/www/${Joomla_DIR}

#sudo mv joomla-*/* /var/www/${Joomla_DIR}

chown -R www-data:www-data /var/www/${Joomla_DIR}
sudo chmod -R 755 /var/www/${Joomla_DIR}