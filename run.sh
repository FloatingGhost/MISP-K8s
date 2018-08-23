#!/bin/bash
#
# MISP docker startup script
# Xavier Mertens <xavier@rootshell.be>
#
# 2017/05/17 - Created
# 2017/05/31 - Fixed small errors
#

set -e

if [ -r /.firstboot.tmp ]; then
        echo "Container started for the fist time. Setup might time a few minutes. Please wait..."
        echo "(Details are logged in /tmp/install.log)"
        export DEBIAN_FRONTEND=noninteractive

        echo "Configuring postfix"
        if [ -z "$POSTFIX_RELAY_HOST" ]; then
                echo "POSTFIX_RELAY_HOST is not set, please configure Postfix manually later..."
        else
                postconf -e "relayhost = $POSTFIX_RELAY"
        fi

        sed -i "s|-o smtp_fallback_relay=||" /etc/postfix/master.cf

        if [ ! -z "$POSTFIX_EXTRA_CONFIG" ]; then
               echo "postconf -e $POSTFIX_EXTRA_CONFIG";
               postconf -e $POSTFIX_EXTRA_CONFIG;
        fi

        if [ ! -z "$SMTP_USERNAME" ]; then
                echo "$POSTFIX_RELAY_HOST $SMTP_USERNAME:$SMTP_PASSWORD" >> /etc/postfix/sasl_password;
                postmap hash:/etc/postfix/sasl_password;
                postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt';
        fi

        # Fix timezone (adapt to your local zone)
        if [ -z "$TIMEZONE" ]; then
                echo "TIMEZONE is not set, please configure the local time zone manually later..."
        else
                echo "$TIMEZONE" > /etc/timezone
                dpkg-reconfigure -f noninteractive tzdata >>/tmp/install.log
        fi

        echo "Creating MySQL database"

        # Check MYSQL_HOST
        if [ -z "$MYSQL_HOST" ]; then
                echo "MYSQL_HOST is not set. Aborting."
                exit 1
        fi

        # Set MYSQL_MISP_PASSWORD
        if [ -z "$MYSQL_MISP_PASSWORD" ]; then
                echo "MYSQL_MISP_PASSWORD is not set, use default value 'misp'"
                MYSQL_MISP_PASSWORD=misp
        else
                echo "MYSQL_MISP_PASSWORD is set to '$MYSQL_MISP_PASSWORD'"
        fi

        ret=`echo 'SHOW TABLES;' | mysql -u misp --password="$MYSQL_MISP_PASSWORD" -h $MYSQL_HOST -P 3306 misp # 2>&1`
        if [ $? -eq 0 ]; then
                echo "Connected to database successfully!"
                found=0
                for table in $ret; do
                        if [ "$table" == "attributes" ]; then
                                found=1
                        fi
                done
                if [ $found -eq 1 ]; then
                        echo "Database misp available"
                else
                        echo "Database misp empty, creating tables ..."
                        ret=`mysql -u misp --password="$MYSQL_MISP_PASSWORD" misp -h $MYSQL_HOST -P 3306 2>&1 < /var/www/MISP/INSTALL/MYSQL.sql`
                        if [ $? -eq 0 ]; then
                            echo "Imported /var/www/MISP/INSTALL/MYSQL.sql successfully"
                        else
                            echo "ERROR: Importing /var/www/MISP/INSTALL/MYSQL.sql failed:"
                            echo $ret
                        fi
                fi
        else
                echo "ERROR: Connecting to database failed:"
                echo $ret
        fi

        # MISP configuration
        echo "Creating MISP configuration files"
        cd /var/www/MISP/app/Config
        cp -a database.default.php database.php
        sed -i "s/localhost/$MYSQL_HOST/" database.php
        sed -i "s/db\s*login/misp/" database.php
        sed -i "s/8889/3306/" database.php
        sed -i "s/db\s*password/$MYSQL_MISP_PASSWORD/" database.php
        # Fix the base url
        if [ -z "$MISP_BASEURL" ]; then
                echo "No base URL defined, don't forget to define it manually!"
        else
                echo "Fixing the MISP base URL ($MISP_BASEURL) ..."
                sed -i "s|'baseurl'\s*=> '.*',|'baseurl' => '$MISP_BASEURL',|" /var/www/MISP/app/Config/config.php
        fi

        # Generate the admin user PGP key
        echo "Creating admin GnuPG key"
        if [ ! -z "$PGP_S3" ]; then
            echo "Retriving PGP key from $PGP_S3";
            aws s3 cp $PGP_S3 private.key;
            sudo -u www-data gpg --homedir /var/www/MISP/.gnupg --import private.key;
        fi

        if [ -z "$MISP_ADMIN_EMAIL" -o -z "$MISP_ADMIN_PASSPHRASE" ]; then
                echo "No admin details provided, don't forget to generate the PGP key manually!"
        else
                echo "Generating admin PGP key ... (please be patient, we need some entropy)"
                cat >/tmp/gpg.tmp <<GPGEOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 2048
Name-Real: MISP Admin
Name-Email: $MISP_ADMIN_EMAIL
Expire-Date: 0
Passphrase: $MISP_ADMIN_PASSPHRASE
%commit
%echo Done
GPGEOF
                sudo -u www-data gpg --homedir /var/www/MISP/.gnupg --gen-key --batch /tmp/gpg.tmp >>/tmp/install.log
                rm -f /tmp/gpg.tmp
        fi

        # Display tips
        cat <<__WELCOME__
Congratulations!
Your MISP docker has been successfully booted for the first time.
Don't forget:
- Reconfigure postfix to match your environment
- Change the MISP admin email address to $MISP_ADMIN_EMAIL

__WELCOME__
        rm -f /.firstboot.tmp
fi

sed -i "s|misp.local|$SERVERNAME|" /etc/apache2/sites-available/misp.conf
sed -i "s|\$REDIS_CONNECTION_STRING|$REDIS_CONNECTION_STRING|" /etc/php/7.2/apache2/php.ini

sudo -u www-data gpg --homedir /var/www/MISP/.gnupg -a --export-key $MISP_ADMIN_EMAIL > /var/www/MISP/app/gpg.asc
python3 /extract_config.py

# Start supervisord
echo "Starting supervisord"
cd /
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
          
