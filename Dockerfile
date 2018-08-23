#
# Dockerfile to build a MISP (https://github.com/MISP/MISP) container
#
# Original docker file by eg5846 (https://github.com/eg5846)
#
# 2016/03/03 - First release
# 2017/06/02 - Updated
# 2018/04/04 - Added objects templates
# 

# We are based on Ubuntu:latest
FROM ubuntu:xenial
MAINTAINER Hannah Ward <hannah.ward2@baesystems.com>

# Install core components
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get dist-upgrade -y && apt-get autoremove -y && apt-get clean
RUN apt-get install -y software-properties-common
RUN apt-get install -y postfix
RUN apt-get install -y mysql-client curl gcc git gnupg-agent make python openssl redis-server sudo vim zip locales

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
RUN add-apt-repository -y ppa:ondrej/php && apt-get update

# Apache
RUN apt-get install -y apache2 apache2-doc apache2-utils
RUN a2dismod status
RUN a2dissite 000-default

# PHP 7.2
RUN apt-get install -y libapache2-mod-php php7.2 php7.2-cli php-crypt-gpg php7.2-dev php7.2-json php7.2-mysql php7.2-opcache php7.2-readline php7.2-redis php7.2-xml php7.2-curl
RUN apt-get install -y php-pear pkg-config libbson-1.0 libmongoc-1.0-0 php-xml php-dev

# Fix php.ini with recommended settings
RUN sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/7.2/apache2/php.ini
RUN sed -i "s/memory_limit = 128M/memory_limit = 512M/" /etc/php/7.2/apache2/php.ini
RUN sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 50M/" /etc/php/7.2/apache2/php.ini
RUN sed -i "s/post_max_size = 8M/post_max_size = 50M/" /etc/php/7.2/apache2/php.ini
RUN sed -i "s/session.save_handler = files/session.save_handler = redis\nsession.save_path = \$REDIS_CONNECTION_STRING/" /etc/php/7.2/apache2/php.ini
 
RUN apt-get install -y python-dev python-pip libxml2-dev libxslt1-dev zlib1g-dev python-setuptools libfuzzy-dev python3-setuptools python3-dev python3-pip libjpeg-dev cron logrotate supervisor syslog-ng-core
RUN apt-get clean

WORKDIR /var/www
RUN chown www-data:www-data /var/www
USER www-data
RUN git clone https://github.com/FloatingGhost/MISP.git
WORKDIR /var/www/MISP
#RUN git checkout tags/$(git describe --tags `git rev-list --tags --max-count=1`)
RUN git config core.filemode false

WORKDIR /var/www/MISP/app/files/scripts
RUN git clone https://github.com/MAECProject/python-maec.git
RUN git clone https://github.com/CybOXProject/mixbox.git
RUN git clone https://github.com/CybOXProject/python-cybox.git
RUN git clone https://github.com/STIXProject/python-stix.git

WORKDIR /var/www/MISP/app/files/scripts/python-cybox
RUN git checkout v2.1.0.17
USER root
RUN python3 setup.py install

USER www-data
WORKDIR /var/www/MISP/app/files/scripts/python-stix
RUN git checkout v1.2.0.6
USER root
RUN python3 setup.py install

USER www-data
WORKDIR /var/www/MISP
RUN git submodule init
RUN git submodule update

USER root
WORKDIR /var/www/MISP/PyMISP
RUN pip3 install jsonschema==2.6.0
RUN python3 setup.py install
WORKDIR /var/www/MISP/app/files/scripts/python-maec
RUN python3 setup.py install

USER www-data
WORKDIR /var/www/MISP/app
RUN php composer.phar config vendor-dir Vendor
RUN php composer.phar require aws/aws-sdk-php
RUN php composer.phar require elasticsearch/elasticsearch
RUN php composer.phar install --ignore-platform-reqs
USER root
RUN phpenmod redis
USER www-data
RUN cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

# Fix permissions
USER root
RUN chown -R www-data:www-data /var/www/MISP
RUN chmod -R 750 /var/www/MISP
RUN chmod -R g+ws /var/www/MISP/app/tmp
RUN chmod -R g+ws /var/www/MISP/app/files
RUN chmod -R g+ws /var/www/MISP/app/files/scripts/tmp

RUN cp /var/www/MISP/INSTALL/misp.logrotate /etc/logrotate.d/misp

# Preconfigure setting for packages
RUN echo "postfix postfix/main_mailer_type string Local only" | debconf-set-selections
RUN echo "postfix postfix/mailname string localhost.localdomain" | debconf-set-selections

# Redis Setup
RUN sed -i 's/^\(daemonize\s*\)yes\s*$/\1no/g' /etc/redis/redis.conf

# Install PEAR packages
RUN pear install Crypt_GPG >>/tmp/install.log
RUN pear install Net_GeoIP >>/tmp/install.log

# Apache Setup
RUN cp /var/www/MISP/INSTALL/apache.misp.ubuntu /etc/apache2/sites-available/misp.conf
RUN a2dissite 000-default
RUN a2ensite misp
RUN a2enmod rewrite
RUN a2enmod headers

# MISP base configuration
RUN sudo -u www-data cp -a /var/www/MISP/app/Config/bootstrap.default.php /var/www/MISP/app/Config/bootstrap.php
RUN sudo -u www-data cp -a /var/www/MISP/app/Config/database.default.php /var/www/MISP/app/Config/database.php
RUN sudo -u www-data cp -a /var/www/MISP/app/Config/core.default.php /var/www/MISP/app/Config/core.php
RUN sudo -u www-data cp -a /var/www/MISP/app/Config/config.default.php /var/www/MISP/app/Config/config.php
RUN chown -R www-data:www-data /var/www/MISP/app/Config
RUN chmod -R 750 /var/www/MISP/app/Config

# Replace the default salt
RUN sed -i -E "s/'salt'\s=>\s'(\S+)'/'salt' => '`openssl rand -base64 32|tr "/" "-"`'/" /var/www/MISP/app/Config/config.php

# Enable workers at boot time
RUN chmod a+x /var/www/MISP/app/Console/worker/start.sh
RUN echo "sudo -u www-data bash /var/www/MISP/app/Console/worker/start.sh" >>/etc/rc.local

# Install templates & stuff
WORKDIR /var/www/MISP/app/files
RUN rm -rf misp-objects && git clone https://github.com/MISP/misp-objects.git
RUN rm -rf misp-galaxy && git clone https://github.com/MISP/misp-galaxy.git
RUN rm -rf warninglists && git clone https://github.com/MISP/misp-warninglists.git ./warninglists
RUN rm -rf taxonomies && git clone https://github.com/MISP/misp-taxonomies.git ./taxonomies
RUN chown -R www-data:www-data misp-objects misp-galaxy warninglists taxonomies

# Install MISP Modules
WORKDIR /opt

USER root
RUN pip3 install --upgrade --ignore-installed setuptools
RUN pip3 install --upgrade --ignore-installed urllib3 
RUN pip3 install --upgrade --ignore-installed requests

# Install extra deps
RUN pip3 install lief
RUN pip3 install git+https://github.com/kbandla/pydeep.git
RUN pip3 install python-magic
RUN pip3 install awscli

# Supervisord Setup
RUN echo '[supervisord]' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'nodaemon = true' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '[program:postfix]' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'process_name = master' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'directory = /etc/postfix' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'command = /usr/sbin/postfix -c /etc/postfix start' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '[program:apache2]' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'command=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -D FOREGROUND"' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '[program:resque]' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'command=/bin/bash /var/www/MISP/app/Console/worker/start.sh' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'user = www-data' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf
RUN echo '' >> /etc/supervisor/conf.d/supervisord.conf

# Modify syslog configuration
RUN sed -i -E 's/^(\s*)system\(\);/\1unix-stream("\/dev\/log");/' /etc/syslog-ng/syslog-ng.conf

# Add yaml to python for the memes (and the config)
RUN pip3 install pyaml

# Add run script
ADD run.sh /run.sh
ADD extract_config.py /extract_config.py
RUN chmod 0755 /run.sh

# Trigger to perform first boot operations
RUN touch /.firstboot.tmp

# Make a backup of /var/www/MISP to restore it to the local moint point at first boot
WORKDIR /var/www/MISP

EXPOSE 80
ENTRYPOINT ["/run.sh"]
