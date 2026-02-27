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

wait_for_db() {
  retries="${OPENCART_DB_WAIT_MAX_RETRIES:-60}"
  interval="${OPENCART_DB_WAIT_INTERVAL_SECONDS:-3}"
  i=0

  echo "Waiting for database ${DB_HOSTNAME}:${DB_PORT} ..."

  while true; do
    if php -r '
      mysqli_report(MYSQLI_REPORT_OFF);
      $host = getenv("DB_HOSTNAME") ?: "mysql";
      $user = getenv("DB_USERNAME") ?: "opencart";
      $pass = getenv("DB_PASSWORD") ?: "";
      $port = (int)(getenv("DB_PORT") ?: "3306");
      $mysqli = @new mysqli($host, $user, $pass, "", $port);
      if ($mysqli->connect_errno) { exit(1); }
      $mysqli->close();
      exit(0);
    '; then
      echo "Database is ready."
      return 0
    fi

    i=$((i + 1))
    if [ "$i" -ge "$retries" ]; then
      echo "Database readiness timed out after ${retries} attempts."
      return 1
    fi

    sleep "$interval"
  done
}

ensure_database() {
  php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $host = getenv("DB_HOSTNAME") ?: "mysql";
    $user = getenv("DB_USERNAME") ?: "opencart";
    $pass = getenv("DB_PASSWORD") ?: "";
    $db   = getenv("DB_DATABASE") ?: "opencart";
    $port = (int)(getenv("DB_PORT") ?: "3306");

    $mysqli = @new mysqli($host, $user, $pass, "", $port);
    if ($mysqli->connect_errno) {
      fwrite(STDERR, "DB connect failed when creating database: " . $mysqli->connect_error . PHP_EOL);
      exit(1);
    }

    $escaped = str_replace("`", "``", $db);
    $sql = "CREATE DATABASE IF NOT EXISTS `{$escaped}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci";
    if (!$mysqli->query($sql)) {
      fwrite(STDERR, "CREATE DATABASE failed: " . $mysqli->error . PHP_EOL);
      $mysqli->close();
      exit(1);
    }

    $mysqli->close();
    exit(0);
  '
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
  if wait_for_db; then
    if ensure_database; then
      if php install/cli_install.php install \
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
        --db_prefix "${DB_PREFIX}"; then
        touch install.lock
        echo "OpenCart auto installation completed."
      else
        echo "OpenCart auto installation failed; installer UI remains available."
      fi
    else
      echo "Database creation/check failed; installer UI remains available."
    fi
  else
    echo "Skip auto installation because database is not reachable."
  fi
fi

if [ "${OPENCART_REMOVE_INSTALLER}" = "true" ] && [ -f install.lock ] && [ -d install ]; then
  rm -rf install
fi

exec "$@"
