#!/usr/bin/env sh
set -eu

cd /var/www/html

STORAGE_PATH="${OPENCART_STORAGE_PATH:-/var/www/storage}"
STORAGE_PATH="${STORAGE_PATH%/}"
if [ -z "${STORAGE_PATH}" ]; then
  STORAGE_PATH="/var/www/storage"
fi

STORAGE_SEED_PATH="${OPENCART_STORAGE_SEED_PATH:-/usr/local/share/opencart/storage-seed}"
STORAGE_SEED_PATH="${STORAGE_SEED_PATH%/}"
if [ -z "${STORAGE_SEED_PATH}" ]; then
  STORAGE_SEED_PATH="/usr/local/share/opencart/storage-seed"
fi

ADMIN_PATH="${OPENCART_ADMIN_PATH:-admin}"
case "${ADMIN_PATH}" in
  *[!a-zA-Z0-9_-]*|"")
    ADMIN_PATH="admin"
    ;;
esac

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

configure_storage_layout() {
  legacy_storage="/var/www/html/system/storage"
  storage_bootstrap_flag="${STORAGE_PATH}/.opencart-storage-bootstrap-complete"
  bootstrap_source=""

  mkdir -p "${STORAGE_PATH}"

  if [ -d "${STORAGE_SEED_PATH}" ]; then
    bootstrap_source="${STORAGE_SEED_PATH}"
  elif [ -d "${legacy_storage}" ] && [ ! -L "${legacy_storage}" ]; then
    bootstrap_source="${legacy_storage}"
  fi

  if [ -n "${bootstrap_source}" ] && [ ! -f "${storage_bootstrap_flag}" ]; then
    # Bootstrap storage data once. Do not rely on directory emptiness:
    # PVC roots may contain lost+found, which would otherwise skip vendor copy.
    cp -an "${bootstrap_source}/." "${STORAGE_PATH}/" || true
    touch "${storage_bootstrap_flag}" || true
  fi

  # Ensure Twig/autoload dependencies exist even for partially initialized PVCs.
  if [ -n "${bootstrap_source}" ] && [ -d "${bootstrap_source}/vendor" ] && [ ! -f "${STORAGE_PATH}/vendor/autoload.php" ]; then
    mkdir -p "${STORAGE_PATH}/vendor"
    cp -an "${bootstrap_source}/vendor/." "${STORAGE_PATH}/vendor/" || true
  fi

  # Keep legacy storage path removed so OpenCart security cleanup actions
  # never target the active storage volume through symlinks.
  if [ -L "${legacy_storage}" ]; then
    rm -f "${legacy_storage}" || true
  elif [ -d "${legacy_storage}" ] && [ "${legacy_storage}" != "${STORAGE_PATH}" ]; then
    rm -rf "${legacy_storage}" || true
  fi

  mkdir -p "${STORAGE_PATH}/cache"
  mkdir -p "${STORAGE_PATH}/logs"
  mkdir -p "${STORAGE_PATH}/download"
  mkdir -p "${STORAGE_PATH}/upload"
  mkdir -p "${STORAGE_PATH}/modification"
  mkdir -p "${STORAGE_PATH}/session"
  mkdir -p "${STORAGE_PATH}/marketplace"
  mkdir -p "${STORAGE_PATH}/backups"

  fix_dir_permissions "${STORAGE_PATH}"
}

rewrite_storage_path_in_config() {
  target="$1"
  if [ ! -f "${target}" ]; then
    return 0
  fi

  escaped_storage=$(printf "%s" "${STORAGE_PATH}/" | sed "s/[&]/\\\\&/g")
  sed -i "s|define('DIR_STORAGE', .*);|define('DIR_STORAGE', '${escaped_storage}');|g" "${target}" || true
  fix_file_permissions "${target}"
}

rewrite_admin_path_in_config() {
  target="$1"
  if [ ! -f "${target}" ]; then
    return 0
  fi

  escaped_admin=$(printf "%s" "${ADMIN_PATH}" | sed "s/[&]/\\\\&/g")
  sed -i "s|/admin/|/${escaped_admin}/|g" "${target}" || true
  sed -i "s|'admin/'|'${escaped_admin}/'|g" "${target}" || true
  fix_file_permissions "${target}"
}

apply_admin_directory_move() {
  if [ "${ADMIN_PATH}" = "admin" ]; then
    return 0
  fi

  if [ ! -f install.lock ]; then
    return 0
  fi

  source_dir="/var/www/html/admin"
  target_dir="/var/www/html/${ADMIN_PATH}"

  if [ -d "${target_dir}" ]; then
    :
  elif [ -d "${source_dir}" ]; then
    mv "${source_dir}" "${target_dir}"
  else
    return 0
  fi

  rewrite_admin_path_in_config "${target_dir}/config.php"
  fix_dir_permissions "${target_dir}"
  echo "OpenCart admin directory set to: ${ADMIN_PATH}"
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

configure_storage_layout
rewrite_storage_path_in_config config.php
rewrite_storage_path_in_config admin/config.php

# OpenCart installer requires writable config files.
fix_file_permissions config.php
fix_file_permissions admin/config.php

# Common writable runtime directories for installer and app runtime.
fix_dir_permissions image
fix_dir_permissions "${STORAGE_PATH}"
fix_dir_permissions "${STORAGE_PATH}/cache"
fix_dir_permissions "${STORAGE_PATH}/logs"
fix_dir_permissions "${STORAGE_PATH}/download"
fix_dir_permissions "${STORAGE_PATH}/upload"

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
        rewrite_storage_path_in_config config.php
        rewrite_storage_path_in_config admin/config.php
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

apply_admin_directory_move

exec "$@"
