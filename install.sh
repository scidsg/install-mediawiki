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

# Create a new directory for the extension
sudo mkdir /var/www/html/mediawiki/extensions/CustomHomepage

# Create a PHP file for the extension in the newly created directory
sudo touch /var/www/html/mediawiki/extensions/CustomHomepage/CustomHomepage.php

# Create a MediaWiki Apache configuration file
sudo bash -c 'cat > /var/www/html/mediawiki/extensions/CustomHomepage/CustomHomepage.php << EOL
<?php
$wgHooks['BeforePageDisplay'][] = 'CustomHomepage::onBeforePageDisplay';

class CustomHomepage {
    public static function onBeforePageDisplay( OutputPage &$out, Skin &$skin ) {
        global $wgTitle;

        if ( $wgTitle->isMainPage() ) {
            $out->addModules( 'ext.CustomHomepage' );
        }

        return true;
    }
}
EOL'

# Create a new directory for the extension's resources
sudo mkdir -p /var/www/html/mediawiki/extensions/CustomHomepage/resources

# Create a new JavaScript file for the extension
sudo touch /var/www/html/mediawiki/extensions/CustomHomepage/resources/customHomepage.js

# Create a MediaWiki Apache configuration file
sudo bash -c 'cat > /var/www/html/mediawiki/extensions/CustomHomepage/resources/customHomepage.js << EOL
mw.loader.using(["mediawiki.api"]).then(function () {
    var api = new mw.Api();

    function createGridItem(title) {
        var gridItem = \$("<div class=\"custom-homepage-grid-item\"></div>");
        var link = \$("<a></a>").attr("href", title.getUrl()).text(title.getMainText());
        gridItem.append(link);
        return gridItem;
    }

    api.get({
        action: "query",
        list: "random",
        rnnamespace: 0,
        rnlimit: 9,
        format: "json"
    }).done(function (data) {
        var gridContainer = \$("<div class=\"custom-homepage-grid\"></div>");
        var titles = data.query.random.map(function (page) {
            return new mw.Title(page.title);
        });

        titles.forEach(function (title) {
            var gridItem = createGridItem(title);
            gridContainer.append(gridItem);
        });

        $("#content").html(gridContainer);
    });
});
EOL'

# Create a new CSS file for the extension
sudo touch /var/www/html/mediawiki/extensions/CustomHomepage/resources/customHomepage.css

# Create a MediaWiki Apache configuration file
sudo bash -c 'cat > /var/www/html/mediawiki/extensions/CustomHomepage/resources/customHomepage.css << EOL
.custom-homepage-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    grid-gap: 1rem;
    padding: 1rem;
}

.custom-homepage-grid-item {
    background-color: #f5f5f5;
    border: 1px solid #ccc;
    padding: 1rem;
    text-align: center;
}
EOL'

# Create a new ResourceLoader module for the extension
sudo touch /var/www/html/mediawiki/extensions/CustomHomepage/extension.json

# Create a MediaWiki Apache configuration file
sudo bash -c 'cat > /var/www/html/mediawiki/extensions/CustomHomepage/extension.json << EOL
{
    "name": "CustomHomepage",
    "author": "Your Name",
    "url": "https://www.example.com",
    "descriptionmsg": "Custom MediaWiki homepage with a three-column grid",
    "version": "1.0.0",
    "type": "validextensionclass",
    "manifest_version": 2,
    "AutoloadClasses": {
        "CustomHomepage": "CustomHomepage.php"
    },
    "ResourceModules": {
        "ext.CustomHomepage": {
            "scripts": "resources/customHomepage.js",
            "styles": "resources/customHomepage.css",
            "dependencies": [
                "mediawiki.Title",
                "mediawiki.util"
            ],
            "localBasePath": "",
            "remoteExtPath": "CustomHomepage"
        }
    },
    "Hooks": {
        "BeforePageDisplay": [
            "CustomHomepage::onBeforePageDisplay"
        ]
    }
}
EOL'

# Enable the extension by adding the following line to your LocalSettings.php file
echo "wfLoadExtension( 'CustomHomepage' );" | sudo tee -a /var/www/html/mediawiki/LocalSettings.php
echo "\$wgServer = 'localhost';" | sudo tee -a /var/www/html/mediawiki/LocalSettings.php

# Clear the MediaWiki cache
sudo rm /var/www/html/mediawiki/cache/*

# Restart the Apache server
sudo systemctl restart apache2

# Done
echo "MediaWiki has been installed. Please visit http://mediawiki.local to complete the setup and apply the Vector skin."
