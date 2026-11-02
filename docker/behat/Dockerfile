# Behat executor image — OPTIONAL pre-bake.
#
# The Behat jobs run fine directly on cimg/php:<ver>-browsers with a 15s
# `apt-get install mariadb-client` step (see README.md). This Dockerfile only
# exists to shave that step off if the shard count ever makes it worth
# publishing an image. Until then, do not build or publish this.
#
# Build:  ./build.sh 8.2          -> ghcr.io/helloworlddevs/behat-php:8.2
#         ./build.sh 8.3 --push
ARG PHP_VERSION=8.2
FROM cimg/php:${PHP_VERSION}-browsers

# Everything the Behat jobs need that cimg/php:*-browsers does not already
# ship. PHP (+ gd/pdo_mysql/mbstring/xml/curl/bcmath/zip/intl), composer, git,
# sudo, dockerize, jq, node and Google Chrome are all in the base image.
RUN sudo apt-get update -qq \
 && sudo apt-get install -y -qq --no-install-recommends mariadb-client \
 && sudo rm -rf /var/lib/apt/lists/*
