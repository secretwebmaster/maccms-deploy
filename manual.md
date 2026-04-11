# MacCMS 自動部署使用手冊（zh_TW）

## 1. 快速部署

建議每次都加上時間戳，避免抓到快取舊版：

```bash
curl -fsSL "https://raw.githubusercontent.com/secretwebmaster/maccms-deploy/main/install.sh?ts=$(date +%s)" -o /tmp/install.sh
bash /tmp/install.sh \
  --domain=example.com \
  --db_name=example_com \
  --db_user=example_com \
  --db_pass='123456789' \
  --site_type=adult \
  --route=1 \
  --theme=wntheme26
```

## 2. 最小必要參數

- `--domain`
- `--db_name`
- `--db_user`
- `--db_pass`

其餘參數都有預設值（例如 `--db_host=127.0.0.1`、`--db_port=3306`、`--site_type=movie`）。

## 3. 常用可選參數

- `--site_type=movie|adult`
- `--theme=wntheme26`
- `--site-name=你的站名`
- `--db_host=127.0.0.1`
- `--db_port=3306`
- `--db_prefix=mac_`
- `--admin_user=demoadmin`
- `--admin_pass='p123456789'`
- `--key=github_pat_xxx`（存取私有 repo 時使用）
- `--git_repo=https://github.com/secretwebmaster/maccms.git`

## 4. 私有 Repo 與 PAT

- `maccms` 或 `theme` 若是私有 repo，需要可讀取權限的 PAT。
- 建議使用 Fine-grained PAT，權限給 `Contents: Read-only` 即可。
- 可用 `--key=...` 傳入，或先 `export GITHUB_KEY=...`。

## 5. 部署流程摘要

腳本會依序：

1. 下載並同步 MacCMS 到 `/www/wwwroot/{domain}`（保留 `.well-known`、`.user.ini`）
2. 依 `site_type` 覆蓋 `overlay/movie` 或 `overlay/adult` 核心檔案
3. 建立資料庫設定 `application/database.php`
4. 若資料表不存在，先匯入基礎 schema（MacCMS install.sql）
5. 匯入站點 SQL（`movie_2026.sql` 或 `adult_2026.sql`）
6. 更新 `application/extra/maccms.php`（站名、網域、主題等）
7. 建立 `application/data/install/install.lock`
8. 更新 aaPanel rewrite：`/www/server/panel/vhost/rewrite/{domain}.conf`

## 6. 主題規則

當指定 `--theme=wntheme26`：

- 會下載 `https://github.com/secretwebmaster/wntheme26`
- 目標路徑：`/www/wwwroot/{domain}/template/wntheme26`
- 並自動把 `template_dir`、`mob_template_dir` 更新為 `wntheme26`

## 7. 常見問題

### Q1: 為什麼看到安裝精靈？

通常是 `install.lock` 尚未建立。請確認：

`/www/wwwroot/{domain}/application/data/install/install.lock`

### Q2: 為什麼抓到舊版 install.sh？

請使用帶 `?ts=$(date +%s)` 的 URL 強制略過快取。

### Q3: 為什麼不需要 PAT 也能跑？

若目標 repo 是公開的，就不需要 PAT；只有私有 repo 才需要。

## 8. 建議測試方式

先在測試網域驗證：

1. 首頁可正常開啟
2. 後台可登入
3. 採集源可用
4. 主題套用成功
5. rewrite 規則生效
