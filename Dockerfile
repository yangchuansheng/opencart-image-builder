FROM php:8.3-apache

ARG OPENCART_VERSION=unknown

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      libfreetype6-dev \
      libjpeg62-turbo-dev \
      libpng-dev \
      libzip-dev \
      unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd mysqli pdo_mysql zip \
    && a2enmod rewrite \
    && sed -ri "s!/var/www/html!/var/www/html!g" /etc/apache2/sites-available/*.conf \
    && rm -rf /var/lib/apt/lists/*

COPY source/upload/ /var/www/html/
COPY docker/entrypoint.sh /usr/local/bin/opencart-entrypoint

RUN chmod +x /usr/local/bin/opencart-entrypoint \
    && chown -R www-data:www-data /var/www/html

ENV OPENCART_VERSION="${OPENCART_VERSION}"
ENV OPENCART_AUTO_INSTALL=false
ENV OPENCART_REMOVE_INSTALLER=false
ENV OPENCART_USERNAME=admin
ENV OPENCART_PASSWORD=admin
ENV OPENCART_ADMIN_EMAIL=admin@example.com
ENV OPENCART_HTTP_SERVER=http://localhost/
ENV DB_DRIVER=mysqli
ENV DB_HOSTNAME=mysql
ENV DB_USERNAME=opencart
ENV DB_PASSWORD=opencart
ENV DB_DATABASE=opencart
ENV DB_PORT=3306
ENV DB_PREFIX=oc_
ENV OPENCART_DB_WAIT_MAX_RETRIES=60
ENV OPENCART_DB_WAIT_INTERVAL_SECONDS=3

ENTRYPOINT ["opencart-entrypoint"]
CMD ["apache2-foreground"]
