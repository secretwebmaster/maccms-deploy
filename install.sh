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

# 1) Clone maccms repo when target does not exist
if [ ! -d "$WWW_ROOT" ]; then
  echo "[INFO] Cloning MacCMS to $WWW_ROOT"
  CLONE_URL="$(build_clone_url "$GIT_REPO" "$GITHUB_KEY")"
  git clone "$CLONE_URL" "$WWW_ROOT"
  if [ -n "$GITHUB_KEY" ]; then
    # Remove token from local origin URL after clone.
    git -C "$WWW_ROOT" remote set-url origin "$GIT_REPO"
  fi
else
  echo "[INFO] $WWW_ROOT already exists, skip clone"
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

# 3) Import SQL
echo "[INFO] Importing SQL into $DB_NAME ..."
mysql \
  -h "$DB_HOST" \
  -P "$DB_PORT" \
  -u "$DB_USER" \
  -p"$DB_PASS" \
  "$DB_NAME" < "$SQL_PATH"

echo "[OK] MacCMS clone + database SQL import completed."

if [ -n "$TMP_SQL" ] && [ -f "$TMP_SQL" ]; then
  rm -f "$TMP_SQL"
fi
