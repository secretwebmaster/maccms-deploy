#!/usr/bin/env bash
set -euo pipefail

# Defaults
GIT_REPO="https://github.com/secretwebmaster/maccms.git"
DEPLOY_RAW_BASE="https://raw.githubusercontent.com/secretwebmaster/maccms-deploy/main"
SITE_TYPE="movie"
DB_PORT="3306"
SQL_PATH=""
SQL_URL=""
GITHUB_KEY="${GITHUB_KEY:-}"

usage() {
  cat <<'EOF'
Usage:
  install.sh \
    --domain=example.com \
    --db_host=127.0.0.1 \
    --db_name=example_db \
    --db_user=example_user \
    --db_pass=example_pass \
    [--db_port=3306] \
    [--site_type=movie|adult] \
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
    --db_host=*) DB_HOST="${1#*=}" ; shift ;;
    --db_port=*) DB_PORT="${1#*=}" ; shift ;;
    --db_name=*) DB_NAME="${1#*=}" ; shift ;;
    --db_user=*) DB_USER="${1#*=}" ; shift ;;
    --db_pass=*) DB_PASS="${1#*=}" ; shift ;;
    --site_type=*) SITE_TYPE="${1#*=}" ; shift ;;
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
if [ -z "${DOMAIN:-}" ] || [ -z "${DB_HOST:-}" ] || [ -z "${DB_NAME:-}" ] || [ -z "${DB_USER:-}" ] || [ -z "${DB_PASS:-}" ]; then
  echo "[ERR] Missing required arguments."
  usage
  exit 1
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

  mkdir -p "$target_dir"
  if command -v rsync >/dev/null 2>&1; then
    echo "[INFO] Syncing files to $target_dir (preserve .well-known/.user.ini)"
    rsync -a --delete \
      --exclude ".git" \
      --exclude ".well-known" \
      --exclude ".user.ini" \
      "$tmp_dir"/ "$target_dir"/
  fi
  if ! command -v rsync >/dev/null 2>&1; then
    echo "[WARN] rsync not found, using cp fallback (no delete sync)"
    cp -a "$tmp_dir"/. "$target_dir"/
    rm -rf "$target_dir/.git"
  fi

  rm -rf "$tmp_dir"
}

find_base_schema_sql() {
  local target_dir="$1"
  if [ -f "$target_dir/install/install.sql" ]; then
    echo "$target_dir/install/install.sql"
    return 0
  fi
  if [ -f "$target_dir/install.sql" ]; then
    echo "$target_dir/install.sql"
    return 0
  fi
  if [ -d "$target_dir/install" ]; then
    find "$target_dir/install" -maxdepth 2 -type f -name "*.sql" | head -n 1
    return 0
  fi
  return 1
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

CLONE_URL="$(build_clone_url "$GIT_REPO" "$GITHUB_KEY")"

# 1) Deploy code to web root even if directory already exists
sync_repo_to_www_root "$CLONE_URL" "$WWW_ROOT"
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

# 3) Import base schema if needed
if ! table_exists "mac_type"; then
  BASE_SQL_PATH="$(find_base_schema_sql "$WWW_ROOT" || true)"
  if [ -n "${BASE_SQL_PATH:-}" ] && [ -f "$BASE_SQL_PATH" ]; then
    echo "[INFO] Table mac_type not found, importing base schema: $BASE_SQL_PATH"
    mysql \
      -h "$DB_HOST" \
      -P "$DB_PORT" \
      -u "$DB_USER" \
      -p"$DB_PASS" \
      "$DB_NAME" < "$BASE_SQL_PATH"
  else
    echo "[WARN] Table mac_type not found and base schema SQL not found in $WWW_ROOT"
  fi
fi

# 4) Import site SQL
echo "[INFO] Importing site SQL into $DB_NAME ..."
mysql \
  -h "$DB_HOST" \
  -P "$DB_PORT" \
  -u "$DB_USER" \
  -p"$DB_PASS" \
  "$DB_NAME" < "$SQL_PATH"

echo "[OK] MacCMS code sync + database SQL import completed."

if [ -n "$TMP_SQL" ] && [ -f "$TMP_SQL" ]; then
  rm -f "$TMP_SQL"
fi
