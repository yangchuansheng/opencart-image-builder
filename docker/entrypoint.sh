#!/usr/bin/env sh
set -eu

cd /var/www/html

fix_file_permissions() {
  target="$1"
  if [ -f "$target" ]; then
    chown www-data:www-data "$target" || true
    chmod 664 "$target" || true
  fi
}

fix_dir_permissions() {
  target="$1"
  if [ -d "$target" ]; then
    chown -R www-data:www-data "$target" || true
    chmod -R u+rwX,g+rwX "$target" || true
  fi
}

if [ -f config-dist.php ] && [ ! -f config.php ]; then
  cp config-dist.php config.php
fi

if [ -f admin/config-dist.php ] && [ ! -f admin/config.php ]; then
  cp admin/config-dist.php admin/config.php
fi

if [ -f .htaccess.txt ] && [ ! -f .htaccess ]; then
  cp .htaccess.txt .htaccess
fi

# OpenCart installer requires writable config files.
fix_file_permissions config.php
fix_file_permissions admin/config.php

# Common writable runtime directories for installer and app runtime.
fix_dir_permissions image
fix_dir_permissions system/storage
fix_dir_permissions system/storage/cache
fix_dir_permissions system/storage/logs
fix_dir_permissions system/storage/download
fix_dir_permissions system/storage/upload

if [ "${OPENCART_AUTO_INSTALL}" = "true" ] && [ ! -f install.lock ] && [ -f install/cli_install.php ]; then
  php install/cli_install.php install \
    --username "${OPENCART_USERNAME}" \
    --password "${OPENCART_PASSWORD}" \
    --email "${OPENCART_ADMIN_EMAIL}" \
    --http_server "${OPENCART_HTTP_SERVER}" \
    --db_driver "${DB_DRIVER}" \
    --db_hostname "${DB_HOSTNAME}" \
    --db_username "${DB_USERNAME}" \
    --db_password "${DB_PASSWORD}" \
    --db_database "${DB_DATABASE}" \
    --db_port "${DB_PORT}" \
    --db_prefix "${DB_PREFIX}" || true
fi

if [ "${OPENCART_REMOVE_INSTALLER}" = "true" ] && [ -d install ]; then
  rm -rf install
fi

exec "$@"
