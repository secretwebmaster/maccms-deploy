#!/bin/bash
# MacCMS 一鍵部署腳本
# 2. 後續步驟預留（如：寫入 config、匯入 SQL、覆蓋檔案...）

# 參數預設值
GIT_REPO="https://github.com/secretwebmaster/maccms.git"
SITE_TYPE="movie"

# 參數解析
while [ $# -gt 0 ]; do
  case "$1" in
    --domain=*) DOMAIN="${1#*=}" ; shift ;;
    --db_host=*) DB_HOST="${1#*=}" ; shift ;;
    --db_port=*) DB_PORT="${1#*=}" ; shift ;;
    --db_name=*) DB_NAME="${1#*=}" ; shift ;;
    --db_user=*) DB_USER="${1#*=}" ; shift ;;
    --db_pass=*) DB_PASS="${1#*=}" ; shift ;;
    --site_type=*) SITE_TYPE="${1#*=}" ; shift ;;
    --git_repo=*) GIT_REPO="${1#*=}" ; shift ;;
    *) echo "未知參數: $1"; exit 1 ;;
  esac
done

# 參數檢查
if [ -z "$DOMAIN" ] || [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
  echo "缺少必要參數，請以 --domain= --db_host= --db_name= --db_user= --db_pass= 傳入"
  exit 1
fi

WWW_ROOT="/www/wwwroot/$DOMAIN"

# 1. Clone maccms repo
if [ ! -d "$WWW_ROOT" ]; then
  git clone "$GIT_REPO" "$WWW_ROOT"
else
  echo "$WWW_ROOT 已存在，略過 clone"
fi

# 2. 匯入 install.sql 初始化資料庫
SQL_PATH="$(dirname "$0")/sql/install.sql"
if [ -f "$SQL_PATH" ]; then
  echo "[INFO] 匯入 install.sql 至 $DB_NAME..."
  mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_PATH"
  echo "[OK] install.sql 匯入完成"
else
  echo "[WARN] 找不到 sql/install.sql，略過匯入"
fi

echo "[OK] maccms clone + 資料庫初始化完成，請繼續後續自動化流程設計。"
