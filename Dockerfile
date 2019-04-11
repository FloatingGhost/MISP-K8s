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
RUN apt-get install -y software-properties-common locales 

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
RUN add-apt-repository -y ppa:ondrej/php && apt-get update

RUN apt-get install -y postfix mysql-client curl gcc git gnupg-agent make \
            python openssl redis-server sudo vim zip \
            apache2 apache2-doc apache2-utils libapache2-mod-php php7.2 \
            php7.2-cli php-crypt-gpg php7.2-dev php7.2-json php7.2-mysql \
            php7.2-opcache php7.2-readline php7.2-redis php7.2-xml php7.2-curl \
            php-pear pkg-config libbson-1.0 libmongoc-1.0-0 php-xml php-dev
            python-dev python-pip libxml2-dev libxslt1-dev zlib1g-dev python-setuptools \
            libfuzzy-dev python3-setuptools python3-dev python3-pip libjpeg-dev cron \
            logrotate supervisor syslog-ng-core

RUN a2dismod status
RUN a2dissite 000-default

# Fix php.ini with recommended settings 
RUN sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/7.2/apache2/php.ini && \
    sed -i "s/memory_limit = 128M/memory_limit = 512M/" /etc/php/7.2/apache2/php.ini && \
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 50M/" /etc/php/7.2/apache2/php.ini && \
    sed -i "s/post_max_size = 8M/post_max_size = 50M/" /etc/php/7.2/apache2/php.ini && \
    sed -i "s/session.save_handler = files/session.save_handler = redis\nsession.save_path = \$REDIS_CONNECTION_STRING/" /etc/php/7.2/apache2/php.ini
 
WORKDIR /var/www
RUN chown www-data:www-data /var/www
USER www-data
RUN git clone https://github.com/MISP/MISP.git
WORKDIR /var/www/MISP

RUN git checkout tags/$(git describe --tags `git rev-list --tags --max-count=1`) && \
    git config core.filemode false

WORKDIR /var/www/MISP/app/files/scripts
RUN git clone https://github.com/MAECProject/python-maec.git && \
    git clone https://github.com/CybOXProject/mixbox.git && \
    git clone https://github.com/CybOXProject/python-cybox.git && \
    git clone https://github.com/STIXProject/python-stix.git

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
RUN php composer.phar config vendor-dir Vendor && \
    php composer.phar require aws/aws-sdk-php && \
    php composer.phar require elasticsearch/elasticsearch && \
    php composer.phar install --ignore-platform-reqs

USER root
RUN phpenmod redis
USER www-data
RUN cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

# Fix permissions
USER root

RUN chown -R www-data:www-data /var/www/MISP && \
    chmod -R 750 /var/www/MISP && \
    chmod -R g+ws /var/www/MISP/app/tmp && \
    chmod -R g+ws /var/www/MISP/app/files && \
    chmod -R g+ws /var/www/MISP/app/files/scripts/tmp

RUN cp /var/www/MISP/INSTALL/misp.logrotate /etc/logrotate.d/misp

# Preconfigure setting for packages
RUN echo "postfix postfix/main_mailer_type string Local only" | debconf-set-selections && \
    echo "postfix postfix/mailname string localhost.localdomain" | debconf-set-selections && \
    sed -i 's/^\(daemonize\s*\)yes\s*$/\1no/g' /etc/redis/redis.conf

# Install PEAR packages
RUN pear install Crypt_GPG >>/tmp/install.log && \
    pear install Net_GeoIP >>/tmp/install.log

# Apache Setup
RUN cp /var/www/MISP/INSTALL/apache.misp.ubuntu /etc/apache2/sites-available/misp.conf && \
    a2dissite 000-default && \
    a2ensite misp && \
    a2enmod rewrite && \
    a2enmod headers

# MISP base configuration
RUN sudo -u www-data cp -a /var/www/MISP/app/Config/bootstrap.default.php /var/www/MISP/app/Config/bootstrap.php &&  \
    sudo -u www-data cp -a /var/www/MISP/app/Config/database.default.php /var/www/MISP/app/Config/database.php && \
    sudo -u www-data cp -a /var/www/MISP/app/Config/core.default.php /var/www/MISP/app/Config/core.php && \
    sudo -u www-data cp -a /var/www/MISP/app/Config/config.default.php /var/www/MISP/app/Config/config.php && \
    chown -R www-data:www-data /var/www/MISP/app/Config && \
    chmod -R 750 /var/www/MISP/app/Config && \
    sed -i -E "s/'salt'\s=>\s'(\S+)'/'salt' => '`openssl rand -base64 32|tr "/" "-"`'/" /var/www/MISP/app/Config/config.php && \
    chmod a+x /var/www/MISP/app/Console/worker/start.sh && \
    echo "sudo -u www-data bash /var/www/MISP/app/Console/worker/start.sh" >>/etc/rc.local

# Install templates & stuff
WORKDIR /var/www/MISP/app/files
RUN rm -rf misp-objects && git clone https://github.com/MISP/misp-objects.git && \
    rm -rf misp-galaxy && git clone https://github.com/MISP/misp-galaxy.git && \
    rm -rf warninglists && git clone https://github.com/MISP/misp-warninglists.git ./warninglists && \
    rm -rf taxonomies && git clone https://github.com/MISP/misp-taxonomies.git ./taxonomies && \
    chown -R www-data:www-data misp-objects misp-galaxy warninglists taxonomies

# Install MISP Modules
WORKDIR /opt

USER root
RUN pip3 install --upgrade --ignore-installed setuptools urllib3 requests lief https://github.com/kbandla/pydeep.git python-magic awscli pyaml

# Supervisord Setup
COPY ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Modify syslog configuration
RUN sed -i -E 's/^(\s*)system\(\);/\1unix-stream("\/dev\/log");/' /etc/syslog-ng/syslog-ng.conf

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
