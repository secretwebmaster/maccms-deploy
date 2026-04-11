#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.0.12"

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
THEME=""
SITE_NAME=""

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
    [--theme=wntheme26] \
    [--site-name=MySite] \
    [--admin_user=demoadmin --admin_pass=p123456789] \
    [--install_dir=/] \
    [--lang=zh-cn] \
    [--sql_path=/path/to/file.sql] \
    [--sql_url=https://.../file.sql] \
    [--key=github_fine_grained_pat] \
    [--git_repo=https://github.com/.../maccms.git]
EOF
}

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
    --theme=*) THEME="${1#*=}" ; shift ;;
    --site-name=*) SITE_NAME="${1#*=}" ; shift ;;
    --admin_user=*) ADMIN_USER="${1#*=}" ; shift ;;
    --admin_pass=*) ADMIN_PASS="${1#*=}" ; shift ;;
    --install_dir=*) INSTALL_DIR="${1#*=}" ; shift ;;
    --lang=*) APP_LANG="${1#*=}" ; shift ;;
    --sql_path=*) SQL_PATH="${1#*=}" ; shift ;;
    --sql_url=*) SQL_URL="${1#*=}" ; shift ;;
    --key=*) GITHUB_KEY="${1#*=}" ; shift ;;
    --git_repo=*) GIT_REPO="${1#*=}" ; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERR] unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [ -z "${DOMAIN:-}" ] || [ -z "${DB_NAME:-}" ] || [ -z "${DB_USER:-}" ] || [ -z "${DB_PASS:-}" ]; then
  echo "[ERR] missing required arguments"
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

if [ -z "$ADMIN_USER" ] && [ -z "$ADMIN_PASS" ]; then
  ADMIN_USER="demoadmin"
  ADMIN_PASS="p123456789"
fi

WWW_ROOT="/www/wwwroot/$DOMAIN"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
CACHE_FLAG="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"
if [ -z "$CACHE_FLAG" ]; then CACHE_FLAG="maccms"; fi

mysql_exec() {
  MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$@"
}

mysql_import() {
  local db_name="$1"
  local sql_file="$2"
  MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$db_name" < "$sql_file"
}

resolve_default_sql_ref() {
  case "$SITE_TYPE" in
    movie) echo "sql/movie_2026.sql" ;;
    adult) echo "sql/adult_2026.sql" ;;
    *) echo "[ERR] unsupported --site_type: $SITE_TYPE" >&2; exit 1 ;;
  esac
}

resolve_default_overlay_dir_ref() {
  case "$SITE_TYPE" in
    movie) echo "overlay/movie" ;;
    adult) echo "overlay/adult" ;;
    *) echo "[ERR] unsupported --site_type: $SITE_TYPE" >&2; exit 1 ;;
  esac
}

build_clone_url() {
  local repo_url="$1"
  local key="$2"
  if [ -z "$key" ]; then
    echo "$repo_url"
  elif [[ "$repo_url" == https://github.com/* ]]; then
    echo "${repo_url/https:\/\//https:\/\/x-access-token:${key}@}"
  else
    echo "$repo_url"
  fi
}

sync_repo_to_www_root() {
  local clone_url="$1"
  local target_dir="$2"
  local tmp_dir

  tmp_dir="$(mktemp -d)"
  git clone "$clone_url" "$tmp_dir"
  DEPLOY_REV="$(git -C "$tmp_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"

  mkdir -p "$target_dir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" --exclude ".well-known" --exclude ".user.ini" "$tmp_dir"/ "$target_dir"/
  else
    cp -a "$tmp_dir"/. "$target_dir"/
    rm -rf "$target_dir/.git"
  fi

  rm -rf "$tmp_dir"
}

deploy_overlay_dir_if_needed() {
  local target_dir="$1"
  local overlay_ref
  local overlay_local_dir
  local overlay_source_dir=""
  local tmp_deploy_repo=""

  overlay_ref="$(resolve_default_overlay_dir_ref)"
  overlay_local_dir="$SCRIPT_DIR/$overlay_ref"

  if [ "$SITE_TYPE" = "movie" ]; then
    echo "[INFO] 正在覆蓋 movie 核心檔案"
  elif [ "$SITE_TYPE" = "adult" ]; then
    echo "[INFO] 正在覆蓋 adult 核心檔案"
  fi

  if [ -d "$overlay_local_dir" ]; then
    overlay_source_dir="$overlay_local_dir"
  else
    tmp_deploy_repo="$(mktemp -d)"
    git clone --depth 1 --quiet "https://github.com/secretwebmaster/maccms-deploy.git" "$tmp_deploy_repo" >/dev/null 2>&1
    overlay_source_dir="$tmp_deploy_repo/$overlay_ref"
  fi

  if [ ! -d "$overlay_source_dir" ]; then
    echo "[ERR] overlay dir not found: $overlay_source_dir"
    exit 1
  fi

  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$overlay_source_dir"/ "$target_dir"/
  else
    cp -a "$overlay_source_dir"/. "$target_dir"/
  fi

  if [ -n "$tmp_deploy_repo" ] && [ -d "$tmp_deploy_repo" ]; then
    rm -rf "$tmp_deploy_repo"
  fi
}

deploy_theme_if_needed() {
  local target_dir="$1"
  local theme_name="$2"
  local theme_repo=""
  local theme_clone_url=""
  local theme_dir=""
  local tmp_theme_dir=""

  if [ -z "$theme_name" ]; then
    return 0
  fi

  theme_repo="https://github.com/secretwebmaster/${theme_name}.git"
  theme_clone_url="$(build_clone_url "$theme_repo" "$GITHUB_KEY")"
  theme_dir="$target_dir/template/$theme_name"
  tmp_theme_dir="$(mktemp -d)"

  echo "[INFO] 正在下載主題: $theme_name"
  if ! git clone --quiet "$theme_clone_url" "$tmp_theme_dir" >/dev/null 2>&1; then
    echo "[ERR] 主題下載失敗: $theme_name"
    rm -rf "$tmp_theme_dir"
    exit 1
  fi

  mkdir -p "$theme_dir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" "$tmp_theme_dir"/ "$theme_dir"/
  else
    cp -a "$tmp_theme_dir"/. "$theme_dir"/
    rm -rf "$theme_dir/.git"
  fi

  rm -rf "$tmp_theme_dir"
  echo "[INFO] 成功下載主題: $theme_name"
}

ensure_webroot_owner() {
  local target_dir="$1"
  local owner_now=""

  if id -u www >/dev/null 2>&1 && getent group www >/dev/null 2>&1; then
    if ! chown -R www:www "$target_dir" 2>/dev/null; then
      if command -v find >/dev/null 2>&1; then
        find "$target_dir" -path "$target_dir/.user.ini" -prune -o -exec chown www:www {} + 2>/dev/null || true
      fi
    fi
    owner_now="$(stat -c '%U:%G' "$target_dir" 2>/dev/null || echo unknown)"
    if [ "$owner_now" != "www:www" ]; then
      echo "[WARN] directory owner not www:www: $target_dir => $owner_now"
    fi
  else
    echo "[WARN] user/group www:www not found, skip chown"
  fi
}

table_exists() {
  local table_name="$1"
  local result
  result="$(mysql_exec -N -s -D "$DB_NAME" -e "SHOW TABLES LIKE '$table_name';" 2>/dev/null || true)"
  [ "$result" = "$table_name" ]
}

schema_exists() {
  table_exists "${DB_PREFIX}type" && table_exists "${DB_PREFIX}admin"
}

ensure_database_exists() {
  mysql_exec -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8;"
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

  echo "[INFO]  正在匯入 $label 到 $DB_NAME ..."
  mysql_import "$DB_NAME" "$sql_to_import"

  if [ -n "$tmp_sql" ] && [ -f "$tmp_sql" ]; then
    rm -f "$tmp_sql"
  fi
}

import_base_schema_if_needed() {
  local target_dir="$1"
  local base_install_sql=""
  local base_init_sql=""

  if schema_exists; then
    return 0
  fi

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
    echo "[WARN] 找不到 MacCMS 基礎 schema SQL: $target_dir"
    return 0
  fi

  echo "[INFO] 找不到既有 MacCMS schema，正在匯入基礎 schema: $base_install_sql"
  import_sql_with_prefix "$base_install_sql" "$(basename "$base_install_sql")"

  if [ "$INITDATA" = "1" ] && [ -n "$base_init_sql" ]; then
    import_sql_with_prefix "$base_init_sql" "initdata.sql"
  fi
}

update_maccms_config() {
  local target_dir="$1"
  local theme_name="$2"
  local conf_file="$target_dir/application/extra/maccms.php"

  mkdir -p "$(dirname "$conf_file")"
  if [ ! -f "$conf_file" ]; then
    echo "[WARN] config not found, skip update: $conf_file"
    return 0
  fi

  if ! command -v php >/dev/null 2>&1; then
    echo "[WARN] php not found, skip maccms.php update"
    return 0
  fi

  php -r '
    $file = $argv[1];
    $installDir = $argv[2];
    $lang = $argv[3];
    $theme = $argv[4];
    $domain = $argv[5];
    $cacheFlag = $argv[6];
    $siteName = $argv[7];
    $cfg = include $file;
    if (!is_array($cfg)) { $cfg = []; }
    if (!isset($cfg["app"]) || !is_array($cfg["app"])) { $cfg["app"] = []; }
    if (!isset($cfg["site"]) || !is_array($cfg["site"])) { $cfg["site"] = []; }
    if (!isset($cfg["interface"]) || !is_array($cfg["interface"])) { $cfg["interface"] = []; }
    if (!isset($cfg["api"]) || !is_array($cfg["api"])) { $cfg["api"] = []; }
    if (!isset($cfg["api"]["vod"]) || !is_array($cfg["api"]["vod"])) { $cfg["api"]["vod"] = []; }
    if (!isset($cfg["api"]["art"]) || !is_array($cfg["api"]["art"])) { $cfg["api"]["art"] = []; }
    $cfg["app"]["cache_flag"] = $cacheFlag;
    $cfg["app"]["lang"] = $lang;
    $cfg["site"]["install_dir"] = $installDir;
    $cfg["site"]["site_url"] = $domain;
    $cfg["site"]["site_wapurl"] = $domain;
    if (!empty($siteName)) { $cfg["site"]["site_name"] = $siteName; }
    if (!empty($theme)) {
      $cfg["site"]["template_dir"] = $theme;
      $cfg["site"]["mob_template_dir"] = $theme;
    }
    $cfg["interface"]["status"] = 0;
    $cfg["interface"]["pass"] = strtoupper(substr(md5(uniqid("", true)), 0, 16));
    $cfg["api"]["vod"]["status"] = 0;
    $cfg["api"]["art"]["status"] = 0;
    $body = "<?php\nreturn " . var_export($cfg, true) . ";\n";
    file_put_contents($file, $body);
  ' "$conf_file" "$INSTALL_DIR" "$APP_LANG" "$theme_name" "$DOMAIN" "$CACHE_FLAG" "$SITE_NAME"
}

create_install_lock() {
  local target_dir="$1"
  local lock_file="$target_dir/application/data/install/install.lock"
  mkdir -p "$(dirname "$lock_file")"
  date '+%Y-%m-%d %H:%M:%S' > "$lock_file"
}

ensure_admin_account() {
  local table_name="${DB_PREFIX}admin"
  local admin_count
  local admin_pwd_md5
  local admin_random
  local esc_user

  if ! table_exists "$table_name"; then
    return 0
  fi

  admin_count="$(mysql_exec -N -s -D "$DB_NAME" -e "SELECT COUNT(*) FROM \`$table_name\`;" 2>/dev/null || echo "0")"
  if [ "$admin_count" != "0" ]; then
    return 0
  fi

  if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "[WARN] no admin found and no --admin_user/--admin_pass provided"
    return 0
  fi

  admin_pwd_md5="$(printf '%s' "$ADMIN_PASS" | md5sum | awk '{print $1}')"
  admin_random="$(date +%s%N | md5sum | awk '{print $1}')"
  esc_user="$(printf '%s' "$ADMIN_USER" | sed "s/'/''/g")"

  mysql_exec -D "$DB_NAME" -e "INSERT INTO \`$table_name\` (\`admin_name\`,\`admin_pwd\`,\`admin_random\`,\`admin_status\`,\`admin_auth\`) VALUES ('$esc_user','$admin_pwd_md5','$admin_random',1,'');"
}

update_nginx_rule() {
  local conf_file="/www/server/panel/vhost/rewrite/${DOMAIN}.conf"
  local backup_file="${conf_file}.bak.$(date +%s)"
  local tmp_file

  mkdir -p "$(dirname "$conf_file")"
  if [ -f "$conf_file" ]; then
    cp "$conf_file" "$backup_file"
  fi

  tmp_file="$(mktemp)"
  cat > "$tmp_file" <<'EOF'
location / {
if (!-e $request_filename) {
  rewrite ^/index.php(.*)$ /index.php?s=$1 last;
  rewrite ^/admin.php(.*)$ /admin.php?s=$1 last;
  rewrite ^/api.php(.*)$ /api.php?s=$1 last;
  rewrite ^(.*)$ /index.php?s=$1 last;
  break;
  }
}
EOF
  mv "$tmp_file" "$conf_file"

  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      nginx -s reload >/dev/null 2>&1 || systemctl reload nginx >/dev/null 2>&1 || service nginx reload >/dev/null 2>&1 || true
    else
      if [ -f "$backup_file" ]; then
        cp "$backup_file" "$conf_file"
      fi
    fi
  fi
}

CLONE_URL="$(build_clone_url "$GIT_REPO" "$GITHUB_KEY")"

sync_repo_to_www_root "$CLONE_URL" "$WWW_ROOT"
deploy_theme_if_needed "$WWW_ROOT" "$THEME"
deploy_overlay_dir_if_needed "$WWW_ROOT"
ensure_webroot_owner "$WWW_ROOT"
if [ -n "$GITHUB_KEY" ] && [ -d "$WWW_ROOT/.git" ]; then
  git -C "$WWW_ROOT" remote set-url origin "$GIT_REPO" || true
fi

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
  SQL_URL="${SQL_URL:-$DEPLOY_RAW_BASE/$SQL_REF}"
  TMP_SQL="$(mktemp)"
  curl -fsSL "$SQL_URL" -o "$TMP_SQL"
  SQL_PATH="$TMP_SQL"
fi

ensure_database_exists
write_database_php_config "$WWW_ROOT"
import_base_schema_if_needed "$WWW_ROOT"
import_sql_with_prefix "$SQL_PATH" "install.sql"
update_maccms_config "$WWW_ROOT" "$THEME"
create_install_lock "$WWW_ROOT"
ensure_admin_account
update_nginx_rule

echo "[OK] MacCMS 自動部署流程完成。source_rev=$DEPLOY_REV"

if [ -n "$TMP_SQL" ] && [ -f "$TMP_SQL" ]; then
  rm -f "$TMP_SQL"
fi
