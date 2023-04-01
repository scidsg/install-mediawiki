#!/bin/bash

# Update and upgrade packages
sudo apt update && sudo apt upgrade -y

# Install necessary packages
sudo apt install -y nginx php-fpm php-mysql php-intl mariadb-server tor

# Configure MariaDB
sudo mysql_secure_installation

# Create a database and user for MediaWiki
sudo mysql -e "CREATE DATABASE mediawiki;"
sudo mysql -e "CREATE USER 'mediawiki'@'localhost' IDENTIFIED BY 'your_password_here';"
sudo mysql -e "GRANT ALL PRIVILEGES ON mediawiki.* TO 'mediawiki'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Download and extract MediaWiki
wget https://releases.wikimedia.org/mediawiki/1.37/mediawiki-1.37.0.tar.gz
tar xvzf mediawiki-*.tar.gz
sudo mkdir -p /var/www/html/mediawiki
sudo mv mediawiki-1.37.0/* /var/www/html/mediawiki

# Configure Nginx
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
sudo bash -c 'cat <<EOT > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name localhost;
    root /var/www/html/mediawiki;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    }
}
EOT'
sudo systemctl restart nginx

# Configure Tor Onion Service
sudo bash -c 'cat <<EOT >> /etc/tor/torrc
HiddenServiceDir /var/lib/tor/mediawiki_hidden_service/
HiddenServicePort 80 127.0.0.1:80
EOT'
sudo systemctl restart tor

# Output Tor Onion address
onion_address=$(sudo cat /var/lib/tor/mediawiki_hidden_service/hostname)
echo "Your MediaWiki installation is accessible via this Onion address:"
echo "$onion_address"
