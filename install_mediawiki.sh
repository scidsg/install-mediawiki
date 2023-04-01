#!/bin/bash

# Update and upgrade packages
sudo apt update && sudo apt upgrade -y

# Install necessary packages
sudo apt install -y nginx php-fpm php-mysql php-intl mariadb-server tor whiptail

# Get user input using whiptail
DB_USER=$(whiptail --inputbox "Please enter a username for the database user:" 8 78 --title "Database Username" 3>&1 1>&2 2>&3)
DB_PASSWORD=$(whiptail --passwordbox "Please enter a password for the '$DB_USER' database user:" 8 78 --title "Database Password" 3>&1 1>&2 2>&3)
SKIN_NAME=$(whiptail --inputbox "Please enter a name for your custom skin (e.g., MyCustomSkin):" 8 78 --title "Skin Name" 3>&1 1>&2 2>&3)
AUTHOR_NAME=$(whiptail --inputbox "Please enter your name (author of the custom skin):" 8 78 --title "Author Name" 3>&1 1>&2 2>&3)
AUTHOR_URL=$(whiptail --inputbox "Please enter your website URL (author of the custom skin):" 8 78 --title "Author URL" 3>&1 1>&2 2>&3)

# Configure MariaDB
sudo mysql_secure_installation

# Create a database and user for MediaWiki
sudo mysql -e "CREATE DATABASE mediawiki;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL PRIVILEGES ON mediawiki.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Download and extract MediaWiki
wget https://releases.wikimedia.org/mediawiki/1.39/mediawiki-1.39.3.tar.gz
tar xvzf mediawiki-*.tar.gz
sudo mkdir -p /var/www/html/mediawiki
sudo mv mediawiki*/* /var/www/html/mediawiki

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

# Duplicate Vector skin
cd /var/www/html/mediawiki/skins/
sudo cp -R Vector "$SKIN_NAME"

# Update skin.json
sudo sed -i "s/\"name\": \"Vector\",/\"name\": \"$SKIN_NAME\",/g" "$SKIN_NAME/skin.json"
sudo sed -i "s/\"author\": \"Various\",/\"author\": \"$AUTHOR_NAME\",/g" "$SKIN_NAME/skin.json"
sudo sed -i "s~\"url\": \"https://www.mediawiki.org/wiki/Skin:Vector\",~\"url\": \"$AUTHOR_URL\",~g" "$SKIN_NAME/skin.json"
sudo sed -i "s/\"descriptionmsg\": \"vector-desc\",/\"descriptionmsg\": \"${SKIN_NAME,,}-desc\",/g" "$SKIN_NAME/skin.json"

# Enable the custom skin in LocalSettings.php
cd /var/www/html/mediawiki
sudo bash -c "echo \"wfLoadSkin('$SKIN_NAME');\" >> LocalSettings.php"
sudo bash -c "echo \"\$wgDefaultSkin = '${SKIN_NAME,,}';\" >> LocalSettings.php"

# Write skin.json
sudo bash -c "cat <<EOT > skin.json
{
    \"name\": \"$SKIN_NAME\",
    \"author\": \"$AUTHOR_NAME\",
    \"url\": \"$AUTHOR_URL\",
    \"descriptionmsg\": \"${SKIN_NAME,,}-desc\",
    \"version\": \"1.0\",
    \"license-name\": \"GPL-2.0-or-later\",
    \"type\": \"skin\",
    \"AutoloadClasses\": {
        \"Skin${SKIN_NAME}\": \"MyCustomSkin.php\",
        \"${SKIN_NAME}Template\": \"MyCustomSkinTemplate.php\"
    },
    \"ResourceModules\": {
        \"skins.${SKIN_NAME,,}\": {
EOT"

# Update the skin.json file to include the custom CSS file
sudo bash -c "echo \"    \\\"styles\\\": {\" >> /var/www/html/mediawiki/skins/$SKIN_NAME/skin.json"
sudo bash -c "echo \"        \\\"resources/skins.$SKIN_NAME.styles/custom.css\\\": \\\"all\\\"\" >> /var/www/html/mediawiki/skins/$SKIN_NAME/skin.json"
sudo bash -c "echo \"    },\" >> /var/www/html/mediawiki/skins/$SKIN_NAME/skin.json"

# Add the closing part of the skin.json file
sudo bash -c "cat <<EOT >> skin.json
    },
    \"ResourceFileModulePaths\": {
        \"localBasePath\": \"\",
        \"remoteSkinPath\": \"$SKIN_NAME\"
    }
}
EOT"

# Write MyCustomSkin.php
sudo bash -c "cat <<EOT > MyCustomSkin.php
<?php
class Skin${SKIN_NAME} extends SkinTemplate {
    public \$skinname = '${SKIN_NAME,,}';
    public \$stylename = '$SKIN_NAME';
    public \$template = '${SKIN_NAME}Template';

    public function initPage(OutputPage \$out) {
        parent::initPage(\$out);
        \$out->addModuleStyles('skins.${SKIN_NAME,,}');
    }
}
EOT"

# Write MyCustomSkinTemplate.php
sudo bash -c "cat <<EOT > MyCustomSkinTemplate.php
<?php
class ${SKIN_NAME}Template extends BaseTemplate {
    public function execute() {
        \$this->html('headelement');
        // Add your HTML and PHP code for the skin structure here
        \$this->html('bodytext');
        \$this->html('bottomscripts');
        \$this->html('debughtml');
        \$this->html('/body');
        \$this->html('/html');
    }
}
EOT"

# Create CSS file
sudo mkdir -p "/var/www/html/mediawiki/skins/$SKIN_NAME/resources/skins.${SKIN_NAME}.styles/"
sudo touch "/var/www/html/mediawiki/skins/$SKIN_NAME/resources/skins.${SKIN_NAME}.styles/custom.css"

# Enable the custom skin in LocalSettings.php
cd /var/www/html/mediawiki
sudo bash -c "echo \"wfLoadSkin('$SKIN_NAME');\" >> LocalSettings.php"
sudo bash -c "echo \"\$wgDefaultSkin = '${SKIN_NAME,,}';\" >> LocalSettings.php"

# Create LocalSettings.php file
sudo bash -c "cat > /var/www/html/mediawiki/LocalSettings.php" << 'EOT'
<?php
# This file was automatically generated by the MediaWiki 1.39.3
# installer. If you make manual changes, please keep track in case you
# need to recreate them later.
#
# See docs/Configuration.md for all configurable settings
# and their default values, but don't forget to make changes in _this_
# file, not there.
#
# Further documentation for configuration settings may be found at:
# https://www.mediawiki.org/wiki/Manual:Configuration_settings

# Protect against web entry
if ( !defined( 'MEDIAWIKI' ) ) {
    exit;
}


## Uncomment this to disable output compression
# $wgDisableOutputCompression = true;

$wgSitename = "DDoS Vector";
$wgMetaNamespace = "DDoS_Vector";

## The URL base path to the directory containing the wiki;
## defaults for all runtime URL paths are based off of this.
## For more information on customizing the URLs
## (like /w/index.php/Page_title to /wiki/Page_title) please see:
## https://www.mediawiki.org/wiki/Manual:Short_URL
$wgScriptPath = "";

## The protocol and server name to use in fully-qualified URLs
$wgServer = "http://138.68.64.73";

## The URL path to static resources (images, scripts, etc.)
$wgResourceBasePath = $wgScriptPath;

## The URL paths to the logo.  Make sure you change this from the default,
## or else you'll overwrite your logo when you upgrade!
$wgLogos = [
    '1x' => "$wgResourceBasePath/resources/assets/change-your-logo.svg",
    'wordmark' => [
        "src" => "DDoS Skin",
        "width" => 119,
        "height" => 18,
    ],
    'icon' => "$wgResourceBasePath/resources/assets/change-your-logo.svg",
];

## UPO means: this is also a user preference option

$wgEnableEmail = true;
$wgEnableUserEmail = true; # UPO

$wgEmergencyContact = "demo@scidsg.org";
$wgPasswordSender = "demo@scidsg.org";

$wgEnotifUserTalk = false; # UPO
$wgEnotifWatchlist = false; # UPO
$wgEmailAuthentication = true;

## Database settings
$wgDBtype = "mysql";
$wgDBserver = "localhost";
$wgDBname = "mediawiki";
$wgDBuser = "mediawiki";
$wgDBpassword = "your_password_here";

# MySQL specific settings
$wgDBprefix = "mw_";

# MySQL table options to use during installation or update
$wgDBTableOptions = "ENGINE=InnoDB, DEFAULT CHARSET=binary";

# Shared database table
# This has no effect unless $wgSharedDB is also set.
$wgSharedTables[] = "actor";

## Shared memory settings
$wgMainCacheType = CACHE_NONE;
$wgMemCachedServers = [];

## To enable image uploads, make sure the 'images' directory
## is writable, then set this to true:
$wgEnableUploads = false;
#$wgUseImageMagick = true;
#$wgImageMagickConvertCommand = "/usr/bin/convert";

# InstantCommons allows wiki to use images from https://commons.wikimedia.org
$wgUseInstantCommons = true;

# Periodically send a pingback to https://www.mediawiki.org/ with basic data
# about this MediaWiki instance. The Wikimedia Foundation shares this data
# with MediaWiki developers to help guide future development efforts.
$wgPingback = false;

# Site language code, should be one of the list in ./includes/languages/data/Names.php
$wgLanguageCode = "en";

# Time zone
$wgLocaltimezone = "UTC";

## Set $wgCacheDirectory to a writable directory on the web server
## to make your wiki go slightly faster. The directory should not
## be publicly accessible from the web.
#$wgCacheDirectory = "$IP/cache";

$wgSecretKey = "acb983ba3a6c21ac87d45f881cbf5a09e9419d41f3154e0dfb8d44fa47091e59";

# Changing this will log out all existing sessions.
$wgAuthenticationTokenVersion = "1";

# Site upgrade key. Must be set to a string (default provided) to turn on the
# web installer while LocalSettings.php is in place
$wgUpgradeKey = "c9359c4af627e5df";

## For attaching licensing metadata to pages, and displaying an
## appropriate copyright notice / icon. GNU Free Documentation
## License and Creative Commons licenses are supported so far.
$wgRightsPage = ""; # Set to the title of a wiki page that describes your license/copyright
$wgRightsUrl = "https://creativecommons.org/publicdomain/zero/1.0/";
$wgRightsText = "Creative Commons Zero (Public Domain)";
$wgRightsIcon = "$wgResourceBasePath/resources/assets/licenses/cc-0.png";

# Path to the GNU diff3 utility. Used for conflict resolution.
$wgDiff3 = "/usr/bin/diff3";

## Default skin: you can change the default skin. Use the internal symbolic
## names, e.g. 'vector' or 'monobook':
$wgDefaultSkin = "vector";

# Enabled skins.
# The following skins were automatically enabled:
wfLoadSkin( 'MinervaNeue' );
wfLoadSkin( 'MonoBook' );
wfLoadSkin( 'Timeless' );
wfLoadSkin( 'Vector' );


# Enabled extensions. Most of the extensions are enabled by adding
# wfLoadExtension( 'ExtensionName' );
# to LocalSettings.php. Check specific extension documentation for more details.
# The following extensions were automatically enabled:
wfLoadExtension( 'AbuseFilter' );
wfLoadExtension( 'ConfirmEdit' );
wfLoadExtension( 'SpamBlacklist' );
wfLoadExtension( 'TitleBlacklist' );


# End of automatically generated settings.
# Add more configuration options below.
EOT

# Output Tor Onion address
onion_address=$(sudo cat /var/lib/tor/mediawiki_hidden_service/hostname)
echo "Your custom skin has been created and applied to your MediaWiki installation."
echo "Your MediaWiki installation is accessible via this Onion address:"
echo "$onion_address"