#!/usr/bin/env bash
set -euo pipefail

# Defaults
SCRIPT_VERSION="2026.04.11-1"
GIT_REPO="https://github.com/secretwebmaster/maccms.git"
DEPLOY_RAW_BASE="https://raw.githubusercontent.com/secretwebmaster/maccms-deploy/main"
SITE_TYPE="movie"
DB_PORT="3306"
DB_HOST="127.0.0.1"
DB_PREFIX="mac_"
SQL_PATH=""
SQL_URL=""
GITHUB_KEY="${GITHUB_KEY:-}"
INITDATA="0"
ADMIN_USER=""
ADMIN_PASS=""
INSTALL_DIR="/"
APP_LANG="zh-cn"
DEPLOY_REV="unknown"

echo "[INFO] install.sh version: ${SCRIPT_VERSION}"

usage() {
  cat <<'EOF'
Usage:
  install.sh \
    --domain=example.com \
    --db_name=example_db \
    --db_user=example_user \
    --db_pass=example_pass \
    [--db_host=127.0.0.1] \
    [--db_port=3306] \
    [--db_prefix=mac_] \
    [--site_type=movie|adult] \
    [--initdata=0|1] \
    [--admin_user=demoadmin --admin_pass=p123456789] \
    [--install_dir=/] \
    [--lang=zh-cn] \
    [--sql_path=/path/to/file.sql] \
    [--sql_url=https://.../file.sql] \
    [--key=github_fine_grained_pat] \
    [--git_repo=https://github.com/.../maccms.git]
EOF
}

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --domain=*) DOMAIN="${1#*=}" ; shift ;;
    --db_port=*) DB_PORT="${1#*=}" ; shift ;;
    --db_prefix=*) DB_PREFIX="${1#*=}" ; shift ;;
    --db_host=*) DB_HOST="${1#*=}" ; shift ;;
    --db_name=*) DB_NAME="${1#*=}" ; shift ;;
    --db_user=*) DB_USER="${1#*=}" ; shift ;;
    --db_pass=*) DB_PASS="${1#*=}" ; shift ;;
    --site_type=*) SITE_TYPE="${1#*=}" ; shift ;;
    --initdata=*) INITDATA="${1#*=}" ; shift ;;
    --admin_user=*) ADMIN_USER="${1#*=}" ; shift ;;
    --admin_pass=*) ADMIN_PASS="${1#*=}" ; shift ;;
    --install_dir=*) INSTALL_DIR="${1#*=}" ; shift ;;
    --lang=*) APP_LANG="${1#*=}" ; shift ;;
    --sql_path=*) SQL_PATH="${1#*=}" ; shift ;;
    --sql_url=*) SQL_URL="${1#*=}" ; shift ;;
    --key=*) GITHUB_KEY="${1#*=}" ; shift ;;
    --git_repo=*) GIT_REPO="${1#*=}" ; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[ERR] Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate required args
if [ -z "${DOMAIN:-}" ] || [ -z "${DB_NAME:-}" ] || [ -z "${DB_USER:-}" ] || [ -z "${DB_PASS:-}" ]; then
  echo "[ERR] Missing required arguments."
  usage
  exit 1
fi

if ! echo "$DB_PREFIX" | grep -Eq '^[a-z0-9]{1,20}_$'; then
  echo "[ERR] --db_prefix must match ^[a-z0-9]{1,20}_$"
  exit 1
fi

if [ "$INITDATA" != "0" ] && [ "$INITDATA" != "1" ]; then
  echo "[ERR] --initdata must be 0 or 1"
  exit 1
fi

if { [ -n "$ADMIN_USER" ] && [ -z "$ADMIN_PASS" ]; } || { [ -z "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; }; then
  echo "[ERR] --admin_user and --admin_pass must be provided together"
  exit 1
fi

if [ -n "$ADMIN_PASS" ]; then
  pass_len="${#ADMIN_PASS}"
  if [ "$pass_len" -lt 6 ] || [ "$pass_len" -gt 20 ]; then
    echo "[ERR] --admin_pass length must be 6-20"
    exit 1
  fi
fi

# Default admin bootstrap credentials when not provided.
if [ -z "$ADMIN_USER" ] && [ -z "$ADMIN_PASS" ]; then
  ADMIN_USER="demoadmin"
  ADMIN_PASS="p123456789"
fi

WWW_ROOT="/www/wwwroot/$DOMAIN"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

resolve_default_sql_ref() {
  case "$SITE_TYPE" in
    movie) echo "sql/movie_2026.sql" ;;
    adult) echo "sql/adult_2026.sql" ;;
    *)
      echo "[ERR] Unsupported --site_type: $SITE_TYPE (allowed: movie, adult)" >&2
      exit 1
      ;;
  esac
}

build_clone_url() {
  local repo_url="$1"
  local key="$2"

  if [ -z "$key" ]; then
    echo "$repo_url"
    return 0
  fi

  case "$repo_url" in
    https://github.com/*)
      # GitHub PAT over HTTPS for private repo clone.
      echo "${repo_url/https:\/\//https:\/\/x-access-token:${key}@}"
      ;;
    *)
      echo "$repo_url"
      ;;
  esac
}

sync_repo_to_www_root() {
  local clone_url="$1"
  local target_dir="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  echo "[INFO] Cloning MacCMS to temp dir: $tmp_dir"
  git clone "$clone_url" "$tmp_dir"
  DEPLOY_REV="$(git -C "$tmp_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "[INFO] Source revision: $DEPLOY_REV"

  mkdir -p "$target_dir"
  if command -v rsync >/dev/null 2>&1; then
    echo "[INFO] Syncing files to $target_dir (preserve .well-known/.user.ini)"
    rsync -a --delete \
      --exclude ".git" \
      --exclude ".well-known" \
      --exclude ".user.ini" \
      "$tmp_dir"/ "$target_dir"/
  else
    echo "[WARN] rsync not found, using cp fallback (no delete sync)"
    cp -a "$tmp_dir"/. "$target_dir"/
    rm -rf "$target_dir/.git"
  fi

  rm -rf "$tmp_dir"
}

ensure_webroot_owner() {
  local target_dir="$1"
  local owner_now=""
  if id -u www >/dev/null 2>&1 && getent group www >/dev/null 2>&1; then
    echo "[INFO] Setting owner to www:www for $target_dir"
    chown -R www:www "$target_dir"
    owner_now="$(stat -c '%U:%G' "$target_dir" 2>/dev/null || echo unknown)"
    echo "[INFO] Current owner for $target_dir: $owner_now"
  else
    echo "[WARN] User/group www:www not found, skip chown"
  fi
}

table_exists() {
  local table_name="$1"
  local result
  result="$(
    mysql -N -s \
      -h "$DB_HOST" \
      -P "$DB_PORT" \
      -u "$DB_USER" \
      -p"$DB_PASS" \
      -D "$DB_NAME" \
      -e "SHOW TABLES LIKE '$table_name';" || true
  )"
  [ "$result" = "$table_name" ]
}

ensure_database_exists() {
  echo "[INFO] Ensuring database exists: $DB_NAME"
  mysql \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -p"$DB_PASS" \
    -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8;"
}

write_database_php_config() {
  local target_dir="$1"
  local db_file="$target_dir/application/database.php"
  mkdir -p "$(dirname "$db_file")"
  cat > "$db_file" <<EOF
<?php
return [
    'type'            => 'mysql',
    'hostname'        => '${DB_HOST}',
    'database'        => '${DB_NAME}',
    'username'        => '${DB_USER}',
    'password'        => '${DB_PASS}',
    'hostport'        => '${DB_PORT}',
    'dsn'             => '',
    'params'          => [],
    'charset'         => 'utf8',
    'prefix'          => '${DB_PREFIX}',
    'debug'           => false,
    'deploy'          => 0,
    'rw_separate'     => false,
    'master_num'      => 1,
    'slave_no'        => '',
    'fields_strict'   => false,
    'resultset_type'  => 'array',
    'auto_timestamp'  => false,
    'datetime_format' => 'Y-m-d H:i:s',
    'sql_explain'     => false,
    'builder'         => '',
    'query'           => '\\think\\db\\Query',
];
EOF
  echo "[INFO] Wrote DB config: $db_file"
}

import_sql_with_prefix() {
  local sql_file="$1"
  local label="$2"
  local sql_to_import="$sql_file"
  local tmp_sql=""

  if [ ! -f "$sql_file" ]; then
    echo "[ERR] SQL file not found: $sql_file"
    exit 1
  fi

  if [ "$DB_PREFIX" != "mac_" ]; then
    tmp_sql="$(mktemp)"
    sed "s/\`mac_/\`${DB_PREFIX}/g; s/mac_/${DB_PREFIX}/g" "$sql_file" > "$tmp_sql"
    sql_to_import="$tmp_sql"
  fi

  echo "[INFO] Importing $label SQL into $DB_NAME ..."
  mysql \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -p"$DB_PASS" \
    "$DB_NAME" < "$sql_to_import"

  if [ -n "$tmp_sql" ] && [ -f "$tmp_sql" ]; then
    rm -f "$tmp_sql"
  fi
}

import_base_schema_if_needed() {
  local target_dir="$1"
  local base_install_sql=""
  local base_init_sql=""

  if table_exists "${DB_PREFIX}type"; then
    return 0
  fi

  # MacCMS v10 default installer SQL location.
  if [ -f "$target_dir/application/install/sql/install.sql" ]; then
    base_install_sql="$target_dir/application/install/sql/install.sql"
  elif [ -f "$target_dir/install/install.sql" ]; then
    base_install_sql="$target_dir/install/install.sql"
  elif [ -f "$target_dir/install.sql" ]; then
    base_install_sql="$target_dir/install.sql"
  fi

  if [ -f "$target_dir/application/install/sql/initdata.sql" ]; then
    base_init_sql="$target_dir/application/install/sql/initdata.sql"
  fi

  if [ -z "$base_install_sql" ]; then
    echo "[WARN] Table ${DB_PREFIX}type not found and base schema SQL not found in $target_dir"
    return 0
  fi

  echo "[INFO] Table ${DB_PREFIX}type not found, importing base schema: $base_install_sql"
  import_sql_with_prefix "$base_install_sql" "base-schema"

  if [ "$INITDATA" = "1" ] && [ -n "$base_init_sql" ]; then
    echo "[INFO] Importing base init data: $base_init_sql"
    import_sql_with_prefix "$base_init_sql" "base-initdata"
  fi
}

update_maccms_config() {
  local target_dir="$1"
  local conf_file="$target_dir/application/extra/maccms.php"

  mkdir -p "$(dirname "$conf_file")"
  if [ ! -f "$conf_file" ]; then
    echo "[WARN] Config file not found, skip maccms config update: $conf_file"
    return 0
  fi

  if ! command -v php >/dev/null 2>&1; then
    echo "[WARN] php command not found, skip maccms config update"
    return 0
  fi

  php -r '
    $file = $argv[1];
    $installDir = $argv[2];
    $lang = $argv[3];
    $cfg = include $file;
    if (!is_array($cfg)) { $cfg = []; }
    if (!isset($cfg["app"]) || !is_array($cfg["app"])) { $cfg["app"] = []; }
    if (!isset($cfg["site"]) || !is_array($cfg["site"])) { $cfg["site"] = []; }
    if (!isset($cfg["interface"]) || !is_array($cfg["interface"])) { $cfg["interface"] = []; }
    if (!isset($cfg["api"]) || !is_array($cfg["api"])) { $cfg["api"] = []; }
    if (!isset($cfg["api"]["vod"]) || !is_array($cfg["api"]["vod"])) { $cfg["api"]["vod"] = []; }
    if (!isset($cfg["api"]["art"]) || !is_array($cfg["api"]["art"])) { $cfg["api"]["art"] = []; }
    $cfg["app"]["cache_flag"] = substr(md5((string)time()), 0, 10);
    $cfg["app"]["lang"] = $lang;
    $cfg["site"]["install_dir"] = $installDir;
    $cfg["interface"]["status"] = 0;
    $cfg["interface"]["pass"] = strtoupper(substr(md5(uniqid("", true)), 0, 16));
    $cfg["api"]["vod"]["status"] = 0;
    $cfg["api"]["art"]["status"] = 0;
    $body = "<?php\nreturn " . var_export($cfg, true) . ";\n";
    file_put_contents($file, $body);
  ' "$conf_file" "$INSTALL_DIR" "$APP_LANG"

  echo "[INFO] Updated app config: $conf_file"
}

create_install_lock() {
  local target_dir="$1"
  local lock_file="$target_dir/application/data/install/install.lock"
  mkdir -p "$(dirname "$lock_file")"
  date '+%Y-%m-%d %H:%M:%S' > "$lock_file"
  echo "[INFO] Wrote install lock: $lock_file"
}

ensure_admin_account() {
  local table_name="${DB_PREFIX}admin"
  local admin_count
  local admin_pwd_md5
  local admin_random
  local esc_user

  if ! table_exists "$table_name"; then
    echo "[WARN] Admin table not found: $table_name"
    return 0
  fi

  admin_count="$(
    mysql -N -s \
      -h "$DB_HOST" \
      -P "$DB_PORT" \
      -u "$DB_USER" \
      -p"$DB_PASS" \
      -D "$DB_NAME" \
      -e "SELECT COUNT(*) FROM \`$table_name\`;" 2>/dev/null || echo "0"
  )"

  if [ "$admin_count" != "0" ]; then
    echo "[INFO] Admin account already exists, skip bootstrap"
    return 0
  fi

  if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "[WARN] No admin found in DB. Provide --admin_user and --admin_pass to bootstrap one."
    return 0
  fi

  admin_pwd_md5="$(printf '%s' "$ADMIN_PASS" | md5sum | awk '{print $1}')"
  admin_random="$(date +%s%N | md5sum | awk '{print $1}')"
  esc_user="$(printf '%s' "$ADMIN_USER" | sed "s/'/''/g")"

  mysql \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -p"$DB_PASS" \
    -D "$DB_NAME" \
    -e "INSERT INTO \`$table_name\` (\`admin_name\`,\`admin_pwd\`,\`admin_random\`,\`admin_status\`,\`admin_auth\`) VALUES ('$esc_user','$admin_pwd_md5','$admin_random',1,'');"

  echo "[INFO] Bootstrapped admin account: $ADMIN_USER"
}

CLONE_URL="$(build_clone_url "$GIT_REPO" "$GITHUB_KEY")"

# 1) Deploy code to web root even if directory already exists
sync_repo_to_www_root "$CLONE_URL" "$WWW_ROOT"
ensure_webroot_owner "$WWW_ROOT"
if [ -n "$GITHUB_KEY" ] && [ -d "$WWW_ROOT/.git" ]; then
  # Remove token from local origin URL after clone/sync.
  git -C "$WWW_ROOT" remote set-url origin "$GIT_REPO" || true
fi

# 2) Resolve SQL source
TMP_SQL=""
if [ -n "$SQL_PATH" ]; then
  if [ ! -f "$SQL_PATH" ]; then
    echo "[ERR] --sql_path file not found: $SQL_PATH"
    exit 1
  fi
elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$(resolve_default_sql_ref)" ]; then
  SQL_PATH="$SCRIPT_DIR/$(resolve_default_sql_ref)"
else
  SQL_REF="$(resolve_default_sql_ref)"
  if [ -z "$SQL_URL" ]; then
    SQL_URL="$DEPLOY_RAW_BASE/$SQL_REF"
  fi
  TMP_SQL="$(mktemp)"
  echo "[INFO] Downloading SQL from: $SQL_URL"
  curl -fsSL "$SQL_URL" -o "$TMP_SQL"
  SQL_PATH="$TMP_SQL"
fi

# 3) Ensure database + write app DB config
ensure_database_exists
write_database_php_config "$WWW_ROOT"

# 4) Import base schema if needed
import_base_schema_if_needed "$WWW_ROOT"

# 5) Import site SQL
import_sql_with_prefix "$SQL_PATH" "site"

# 6) Update app config and lock install state
update_maccms_config "$WWW_ROOT"
create_install_lock "$WWW_ROOT"

# 7) Optional admin bootstrap
ensure_admin_account

echo "[OK] MacCMS auto deploy steps completed. source_rev=$DEPLOY_REV"

if [ -n "$TMP_SQL" ] && [ -f "$TMP_SQL" ]; then
  rm -f "$TMP_SQL"
fi
