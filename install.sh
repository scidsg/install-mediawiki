#!/bin/bash

# Update the system
sudo apt update
sudo apt -y dist-upgrade
sudo apt -y autoremove

# Install necessary packages
sudo apt install -y apache2 php libapache2-mod-php mariadb-server php-mysql php-xml php-mbstring php-apcu php-intl imagemagick php-gd php-cli curl php-curl git whiptail

# Get the latest MediaWiki version and tarball URL
MW_TARBALL_URL=$(curl -s https://www.mediawiki.org/wiki/Download | grep -oP '(?<=href=")[^"]+(?=\.tar\.gz")' | head -1)
MW_VERSION=$(echo $MW_TARBALL_URL | grep -oP '(?<=mediawiki-)[^/]+')

# Download MediaWiki
wget -O mediawiki-${MW_VERSION}.tar.gz "${MW_TARBALL_URL}.tar.gz"
tar xvzf mediawiki-${MW_VERSION}.tar.gz

# Move MediaWiki to the web server directory
sudo mv mediawiki-${MW_VERSION} /var/www/html/mediawiki

# Set appropriate permissions
sudo chown -R www-data:www-data /var/www/html/mediawiki
sudo chmod -R 755 /var/www/html/mediawiki

# Enable Apache rewrite module
sudo a2enmod rewrite

# Create a MediaWiki Apache configuration file
sudo bash -c 'cat > /etc/apache2/sites-available/mediawiki.conf << EOL
<VirtualHost *:80>
    ServerName mediawiki.local
    DocumentRoot /var/www/html/mediawiki

    <Directory /var/www/html/mediawiki/>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL'

# Enable the MediaWiki site and disable the default site
sudo a2ensite mediawiki
sudo a2dissite 000-default

# Restart Apache
sudo systemctl restart apache2

# Get user input using whiptail
db_name=$(whiptail --inputbox "Please enter your desired database name for MediaWiki:" 8 78 --title "Database Name" 3>&1 1>&2 2>&3)
db_user=$(whiptail --inputbox "Please enter your desired database username for MediaWiki:" 8 78 --title "Database Username" 3>&1 1>&2 2>&3)
db_pass=$(whiptail --passwordbox "Please enter your desired database password for MediaWiki:" 8 78 --title "Database Password" 3>&1 1>&2 2>&3)

# Create the database and user
sudo mysql -e "CREATE DATABASE \`${db_name}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Clone Vector
cd /var/www/html/mediawiki/skins
git clone https://github.com/glenn-sorrentino/MyVectorSkin.git
cd MyVectorSkin/

# Create Rename Script
cat > /var/www/html/mediawiki/skins/MyVectorSkin/rename.py << EOL
import os

OLD_NAME = "Vector"
NEW_NAME = "MyVectorSkin"
OLD_NAME_LOWER = "vector"
NEW_NAME_LOWER = "myvectorskin"

def replace_in_file(file_path, old, new):
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            content = file.read()
    except UnicodeDecodeError:
        # Skip non-text files or files with encoding issues
        return

    content = content.replace(old, new)
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(content)


for root, dirs, files in os.walk('.', topdown=False):
    for name in dirs:
        old_dir = os.path.join(root, name)
        new_dir = os.path.join(root, name.replace(OLD_NAME, NEW_NAME).replace(OLD_NAME_LOWER, NEW_NAME_LOWER))
        if old_dir != new_dir:
            os.rename(old_dir, new_dir)

    for name in files:
        old_file = os.path.join(root, name)
        new_file = os.path.join(root, name.replace(OLD_NAME, NEW_NAME).replace(OLD_NAME_LOWER, NEW_NAME_LOWER))
        if old_file != new_file:
            os.rename(old_file, new_file)
        
        # Replace contents in files
        replace_in_file(new_file, OLD_NAME, NEW_NAME)
        replace_in_file(new_file, OLD_NAME_LOWER, NEW_NAME_LOWER)
EOL
python3 rename.py
rm rename.py

# Done
echo "MediaWiki has been installed. Please visit http://mediawiki.local to complete the setup and apply the Vector skin."
