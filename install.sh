#!/usr/bin/env bash
set -euo pipefail

# Defaults
SCRIPT_VERSION="1.0.6"
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

echo "[INFO] install.sh ?àÊú¨Ôº?{SCRIPT_VERSION}"

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
    --theme=*) THEME="${1#*=}" ; shift ;;
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
      echo "[ERR] ?™Áü•?ÉÊï∏Ôº?1"
      usage
      exit 1
      ;;
  esac
done

# Validate required args
if [ -z "${DOMAIN:-}" ] || [ -z "${DB_NAME:-}" ] || [ -z "${DB_USER:-}" ] || [ -z "${DB_PASS:-}" ]; then
  echo "[ERR] Áº∫Â?ÂøÖË??ÉÊï∏??
  usage
  exit 1
fi

if ! echo "$DB_PREFIX" | grep -Eq '^[a-z0-9]{1,20}_$'; then
  echo "[ERR] --db_prefix ?ºÂ?ÂøÖÈ?Á¨¶Â? ^[a-z0-9]{1,20}_$"
  exit 1
fi

if [ "$INITDATA" != "0" ] && [ "$INITDATA" != "1" ]; then
  echo "[ERR] --initdata ?™ËÉΩ??0 ??1"
  exit 1
fi

if { [ -n "$ADMIN_USER" ] && [ -z "$ADMIN_PASS" ]; } || { [ -z "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; }; then
  echo "[ERR] --admin_user ??--admin_pass ÂøÖÈ??åÊ??ê‰?"
  exit 1
fi

if [ -n "$ADMIN_PASS" ]; then
  pass_len="${#ADMIN_PASS}"
  if [ "$pass_len" -lt 6 ] || [ "$pass_len" -gt 20 ]; then
    echo "[ERR] --admin_pass ?∑Â∫¶ÂøÖÈ???6-20"
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
      echo "[ERR] ‰∏çÊîØ?¥Á? --site_typeÔº?SITE_TYPEÔºàÂ?Ë®±Ô?movie, adultÔº? >&2
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
  echo "[INFO] Ê≠?ú® clone MacCMS ?∞Êö´Â≠òÁõÆ?ÑÔ?$tmp_dir"
  git clone "$clone_url" "$tmp_dir"
  DEPLOY_REV="$(git -C "$tmp_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "[INFO] ‰æÜÊ??àÊú¨Ôº?DEPLOY_REV"

  mkdir -p "$target_dir"
  if command -v rsync >/dev/null 2>&1; then
    echo "[INFO] Ê≠?ú®?åÊ≠•Ê™îÊ???$target_dirÔºà‰???.well-known/.user.iniÔº?
    rsync -a --delete \
      --exclude ".git" \
      --exclude ".well-known" \
      --exclude ".user.ini" \
      "$tmp_dir"/ "$target_dir"/
  else
    echo "[WARN] ?æ‰???rsyncÔºåÊîπ??cp ?ôÊè¥Ôºà‰??ÉÂà™?§Â?È§òÊ?Ê°àÔ?"
    cp -a "$tmp_dir"/. "$target_dir"/
    rm -rf "$target_dir/.git"
  fi

  rm -rf "$tmp_dir"
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

  echo "[INFO] Ê≠?ú®‰∏ãË?‰∏ªÈ?Ôº?theme_name"
  git clone "$theme_clone_url" "$tmp_theme_dir"

  mkdir -p "$theme_dir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git" "$tmp_theme_dir"/ "$theme_dir"/
  else
    cp -a "$tmp_theme_dir"/. "$theme_dir"/
    rm -rf "$theme_dir/.git"
  fi

  rm -rf "$tmp_theme_dir"
  echo "[INFO] ‰∏ªÈ?Â∑≤ÈÉ®ÁΩ≤Âà∞Ôº?theme_dir"
}

ensure_webroot_owner() {
  local target_dir="$1"
  local owner_now=""

  if id -u www >/dev/null 2>&1 && getent group www >/dev/null 2>&1; then
    echo "[INFO] Ê≠?ú®Â∞?$target_dir ?ÅÊ??ÖË®≠??www:www"
    if ! chown -R www:www "$target_dir" 2>/dev/null; then
      echo "[WARN] ?ûËø¥ chown ?ºÁ?Ê¨äÈ??ØË™§ÔºõÂ??íÈô§ .user.ini ÂæåÈ?Ë©?
      if command -v find >/dev/null 2>&1; then
        find "$target_dir" \
          -path "$target_dir/.user.ini" -prune -o \
          -exec chown www:www {} + 2>/dev/null || true
      else
        echo "[WARN] ?æ‰???find ?á‰ª§ÔºåÁï•?éÂ???chown"
      fi
    fi

    owner_now="$(stat -c '%U:%G' "$target_dir" 2>/dev/null || echo unknown)"
    echo "[INFO] $target_dir ?ÆÂ??ÅÊ??ÖÔ?$owner_now"
  else
    echo "[WARN] ?æ‰???www:www ‰ΩøÁî®??Áæ§Á?ÔºåÁï•??chown"
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
  echo "[INFO] Á¢∫Ë?Ë≥áÊ?Â∫´Â??®Ô?$DB_NAME"
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

  echo "[INFO] Â∑≤ÂØ´?•Ë??ôÂ∫´Ë®≠Â?Ê™îÔ?$db_file"
}

import_sql_with_prefix() {
  local sql_file="$1"
  local label="$2"
  local sql_to_import="$sql_file"
  local tmp_sql=""

  if [ ! -f "$sql_file" ]; then
    echo "[ERR] ?æ‰???SQL Ê™îÊ?Ôº?sql_file"
    exit 1
  fi

  if [ "$DB_PREFIX" != "mac_" ]; then
    tmp_sql="$(mktemp)"
    sed "s/\`mac_/\`${DB_PREFIX}/g; s/mac_/${DB_PREFIX}/g" "$sql_file" > "$tmp_sql"
    sql_to_import="$tmp_sql"
  fi

  echo "[INFO] Ê≠?ú®?ØÂÖ• $label SQL ??$DB_NAME ..."
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
    echo "[WARN] ?æ‰??∞Ë??ôË°® ${DB_PREFIX}typeÔºå‰???$target_dir ?æ‰??∞Âü∫Á§?schema SQL"
    return 0
  fi

  echo "[INFO] ?æ‰??∞Ë??ôË°® ${DB_PREFIX}typeÔºåÊ≠£?®ÂåØ?•Âü∫Á§?schemaÔº?base_install_sql"
  import_sql_with_prefix "$base_install_sql" "base-schema"

  if [ "$INITDATA" = "1" ] && [ -n "$base_init_sql" ]; then
    echo "[INFO] Ê≠?ú®?ØÂÖ•?∫Á??ùÂ??ñË??ôÔ?$base_init_sql"
    import_sql_with_prefix "$base_init_sql" "base-initdata"
  fi
}

update_maccms_config() {
  local target_dir="$1"
  local theme_name="$2"
  local conf_file="$target_dir/application/extra/maccms.php"

  mkdir -p "$(dirname "$conf_file")"
  if [ ! -f "$conf_file" ]; then
    echo "[WARN] ?æ‰??∞Ë®≠ÂÆöÊ?ÔºåÁï•??maccms Ë®≠Â??¥Êñ∞Ôº?conf_file"
    return 0
  fi

  if ! command -v php >/dev/null 2>&1; then
    echo "[WARN] ?æ‰???php ?á‰ª§ÔºåÁï•??maccms Ë®≠Â??¥Êñ∞"
    return 0
  fi

  php -r '
    $file = $argv[1];
    $installDir = $argv[2];
    $lang = $argv[3];
    $theme = $argv[4];
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
  ' "$conf_file" "$INSTALL_DIR" "$APP_LANG" "$theme_name"

  echo "[INFO] Â∑≤Êõ¥?∞Á?ÂºèË®≠ÂÆöÊ?Ôº?conf_file"
}

create_install_lock() {
  local target_dir="$1"
  local lock_file="$target_dir/application/data/install/install.lock"

  mkdir -p "$(dirname "$lock_file")"
  date '+%Y-%m-%d %H:%M:%S' > "$lock_file"
  echo "[INFO] Â∑≤Âª∫Á´ãÂ?Ë£ùÈ?Ê™îÔ?$lock_file"
}

ensure_admin_account() {
  local table_name="${DB_PREFIX}admin"
  local admin_count
  local admin_pwd_md5
  local admin_random
  local esc_user

  if ! table_exists "$table_name"; then
    echo "[WARN] ?æ‰??∞ÁÆ°?ÜÂì°Ë≥áÊ?Ë°®Ô?$table_name"
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
    echo "[INFO] ÁÆ°Á??°Â∏≥?üÂ∑≤Â≠òÂú®ÔºåÁï•?éÂ?ÂßãÂ?"
    return 0
  fi

  if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "[WARN] Ë≥áÊ?Â∫´‰∏≠?°ÁÆ°?ÜÂì°Â∏≥Ë??ÇÂèØ?≥ÂÖ• --admin_user ??--admin_pass ?≤Ë??ùÂ??ñ„Ä?
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

  echo "[INFO] Â∑≤Â?ÂßãÂ?ÁÆ°Á??°Â∏≥?üÔ?$ADMIN_USER"
}

update_nginx_rule() {
  local conf_file="/www/server/panel/vhost/rewrite/${DOMAIN}.conf"
  local backup_file="${conf_file}.bak.$(date +%s)"
  local tmp_file=""

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
  echo "[INFO] Â∑≤Êõ¥??nginx rewrite Ë¶èÂ?Ôº?conf_file"

  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      if nginx -s reload >/dev/null 2>&1 || systemctl reload nginx >/dev/null 2>&1 || service nginx reload >/dev/null 2>&1; then
        echo "[INFO] nginx Â∑≤È??∞Ë??•Ë®≠ÂÆ?
      else
        echo "[WARN] nginx Ë™ûÊ?Ê™¢Êü•?êÂ?Ôºå‰??çÊñ∞ËºâÂÖ•Â§±Ê?ÔºåË??ãÂ? reload"
      fi
    else
      if [ -f "$backup_file" ]; then
        cp "$backup_file" "$conf_file"
        echo "[WARN] nginx Ë™ûÊ?Ê™¢Êü•Â§±Ê?ÔºåÂ∑≤?ÑÂ?Ë®≠Â?Ê™îÔ?$backup_file"
      else
        echo "[WARN] nginx Ë™ûÊ?Ê™¢Êü•Â§±Ê?Ôºå‰??°Â?‰ªΩÂèØ?ÑÂ?Ôº?conf_file"
      fi
    fi
  else
    echo "[WARN] ?æ‰???nginx ?á‰ª§ÔºåË??ãÂ?Ê™¢Êü•??reload"
  fi
}

CLONE_URL="$(build_clone_url "$GIT_REPO" "$GITHUB_KEY")"

# 1) Deploy code to web root even if directory already exists
sync_repo_to_www_root "$CLONE_URL" "$WWW_ROOT"
deploy_theme_if_needed "$WWW_ROOT" "$THEME"
ensure_webroot_owner "$WWW_ROOT"
if [ -n "$GITHUB_KEY" ] && [ -d "$WWW_ROOT/.git" ]; then
  git -C "$WWW_ROOT" remote set-url origin "$GIT_REPO" || true
fi

# 2) Resolve SQL source
TMP_SQL=""
if [ -n "$SQL_PATH" ]; then
  if [ ! -f "$SQL_PATH" ]; then
    echo "[ERR] --sql_path ?áÂ?Ê™îÊ?‰∏çÂ??®Ô?$SQL_PATH"
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
  echo "[INFO] Ê≠?ú®‰∏ãË? SQLÔº?SQL_URL"
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
update_maccms_config "$WWW_ROOT" "$THEME"
create_install_lock "$WWW_ROOT"

# 7) Optional admin bootstrap
ensure_admin_account

# 8) Update nginx rewrite rule
update_nginx_rule

echo "[OK] MacCMS ?™Â??®ÁΩ≤ÊµÅÁ?ÂÆåÊ??Çsource_rev=$DEPLOY_REV"

if [ -n "$TMP_SQL" ] && [ -f "$TMP_SQL" ]; then
  rm -f "$TMP_SQL"
fi
