# ARCHIVED — copied verbatim from ~/Sites/atdove/Dockerfile on 2026-09-11.
#
# This is NOT the source of the image currently in use. The pushed
# helloworlddevs/atdove-testing-image:v2 (2026-06-16) was built from an
# uncommitted edit that changed the base to drupal:10-php8.2-apache-bullseye.
# This file still says php8.1 and was last committed 2024-09-16.
#
# Kept only as a record of what the old image layered on. See ../behat/README.md
# for the replacement.
#
# This is the parent image, located at https://hub.docker.com/_/drupal
FROM drupal:7.101-php8.1-apache-bullseye AS base

WORKDIR /

FROM base AS shared
# Install libraries and extensions.
RUN apt-get update
RUN apt-get install -y imagemagick
RUN apt-get install -y libmagickwand-dev
RUN apt-get install -y mariadb-client
RUN apt-get install -y sudo
RUN apt-get install -y vim
RUN apt-get install -y wget
RUN apt-get install -y libssl-dev
RUN apt-get install -y git
RUN apt-get install -y libonig-dev
RUN apt-get install -y nano
RUN apt-get install -y xvfb
RUN apt-get install -y x11-apps
RUN apt-get install -y xorg
RUN apt-get upgrade -y openssl
RUN apt-get install -y chromium
RUN apt-get install -y dbus-x11
RUN apt-get install -y libfreetype6-dev
RUN apt-get install -y libjpeg62-turbo-dev
RUN apt-get install -y libpng-dev
RUN apt-get install -y libgif-dev
RUN apt-get install -y libxss1
RUN apt-get install -y libappindicator1
RUN apt-get install -y libappindicator3-1
RUN apt-get install -y curl
RUN apt-get install -y libcurl4-openssl-dev
RUN apt-get install -y unzip
RUN apt-get install -y jq

# Install Node.js and npm (Version 18.x)
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - \
  && apt-get install -y nodejs

# Update npm to the latest version to avoid potential issues
RUN npm install -g npm@10.8.2

RUN export XDG_RUNTIME_DIR=/tmp
# Install Chrome using Puppeteer
RUN npx @puppeteer/browsers install chrome@128.0.6613.84
RUN npx @puppeteer/browsers install chromedriver@128.0.6613.84

RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install mysqli pdo pdo_mysql bcmath gd mbstring xml curl

# Install Terminus
RUN curl -O https://github.com/pantheon-systems/terminus/releases/download/3.0.5/terminus.phar && \
  chmod +x terminus.phar && \
  mv terminus.phar /usr/local/bin/terminus
# Remove the vanilla Drupal project that comes with the parent image.
RUN rm -rf /var/www/html/*

COPY .ci/test/behat/env/drupal-circleci-behat.conf /etc/apache2/sites-available/
RUN a2ensite drupal-circleci-behat && service apache2 start

# Replace it with this command to download and install Composer
RUN curl -sS https://getcomposer.org/composer-stable.phar -o /usr/local/bin/composer && chmod +x /usr/local/bin/composer

# Install Dockerize.
ENV DOCKERIZE_VERSION=v0.6.0
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
  && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
  && rm dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# Install ImageMagic to take screenshots.
RUN pecl install imagick \
  && docker-php-ext-enable imagick
