# MacCMS 一鍵部署系統規劃（aaPanel 專用）

## 🎯 目標

建立一套 **單指令部署流程**，讓每次為新客戶開站時：

```bash
bash install.sh --domain=xxx --db=xxx ...
```

即可完成整個網站初始化，無需再手動：

* 進 Web UI 安裝
* 匯入 SQL
* 上傳 extra / player 檔案

---

## 🧠 核心設計理念

### ❌ 不再使用 Web UI 安裝

原因：

* 只是寫入 DB config
* 之後會被 SQL 覆蓋
* 無法自動化

### ✅ 改為全 CLI 流程

透過腳本完成：

1. clone 程式
2. 寫 DB config
3. import SQL
4. 覆蓋檔案
5. 設定權限

---

## 🧱 Repo 架構設計

### 1️⃣ 核心程式 repo

```text
secretwebmaster/maccms
```

用途：

* 存放修改過的 MacCMS 核心
* 不包含部署邏輯

---

### 2️⃣ 部署 repo（重點）

```text
secretwebmaster/maccms-deploy
```

---

## 📁 目錄結構

```text
maccms-deploy/
├── install.sh                # 主安裝腳本
├── env.example               # 環境參數範本
├── sql/
│   └── preset.sql            # 預設完整資料庫
├── overlay/
│   ├── application/
│   │   └── extra/
│   │       ├── binding.php
│   │       ├── timming.php
│   │       └── vodplayer.php
│   └── static/
│       └── player/
│           ├── xxx.js
│           └── ...
└── clients/
    ├── client-a.env
    ├── client-b.env
    └── ...
```

---

## ⚙️ install.sh 功能拆解

### 1️⃣ 解析參數

```bash
--domain=
--db_host=
--db_port=
--db_name=
--db_user=
--db_pass=
```

---

### 2️⃣ 環境檢查

檢查：

* git
* mysql client
* rsync
* 目錄是否為空

---

### 3️⃣ clone 專案

```bash
git clone maccms → /www/wwwroot/{domain}
```

---

### 4️⃣ 寫入資料庫設定

直接生成：

```php
application/database.php
```

---

### 5️⃣ 匯入預設資料庫

```bash
mysql < preset.sql
```

⚠️ 覆蓋整個 DB

---

### 6️⃣ 覆蓋額外檔案

```bash
rsync overlay/ → site/
```

包含：

* application/extra/*
* static/player/*

---

### 7️⃣ 建立 install lock

避免進入安裝頁

```bash
application/data/install.lock
```

---

### 8️⃣ 設定權限

```bash
chown -R www:www
chmod 755 dirs
chmod 644 files
chmod 775 runtime/static
```

---

### 9️⃣ 清理暫存

```bash
rm -rf /tmp/*
```

---

## 🚀 使用方式

### 基本用法

```bash
bash install.sh \
  --domain=example.com \
  --db_host=127.0.0.1 \
  --db_port=3306 \
  --db_name=example_db \
  --db_user=example_db \
  --db_pass=xxx
```

---

### 🔥 最終形態（遠端一鍵）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/secretwebmaster/maccms-deploy/main/install.sh) \
  --domain=example.com \
  --db_host=127.0.0.1 \
  --db_port=3306 \
  --db_name=example_db \
  --db_user=example_db \
  --db_pass=xxx
```

---

## 🧩 進階功能（建議實作）

### 1️⃣ 客戶配置檔

```bash
bash install.sh --config=client-a
```

讀取：

```text
clients/client-a.env
```

內容：

```bash
DOMAIN=clienta.com
DB_HOST=127.0.0.1
DB_NAME=clienta_db
DB_USER=clienta_db
DB_PASS=xxx
```

---

### 2️⃣ 自動替換站點資訊

SQL example：

```sql
UPDATE mac_config SET value='${DOMAIN}' WHERE name='site_url';
```

---

### 3️⃣ 多模板支援（未來）

```text
templates/
  ├── default/
  ├── adult/
  └── seo/
```

CLI：

```bash
--template=adult
```

---

### 4️⃣ 自動建 DB（選做）

用 root 帳號：

```bash
CREATE DATABASE xxx;
CREATE USER xxx;
GRANT ALL;
```

---

## ⚠️ 注意事項

### ❗ SQL 覆蓋問題

目前設計是：

```text
完全覆蓋 DB
```

優點：

* 快
* 穩

缺點：

* 不易升級

---

### ❗ MacCMS 設定檔路徑

不同版本可能不同：

```text
application/database.php
```

需確認你的 fork

---

### ❗ PHP 權限

aaPanel 通常用：

```bash
www:www
```

---

## 📌 開發順序（建議）

### Phase 1（先做）

* [ ] install.sh 基本版本
* [ ] preset.sql
* [ ] overlay files
* [ ] CLI 安裝成功

---

### Phase 2

* [ ] config 檔支援
* [ ] domain 自動替換
* [ ] log 輸出

---

### Phase 3

* [ ] template 系統
* [ ] DB 自動建立
* [ ] 多版本管理

---

## ✅ 最終成果

你之後開新站只需要：

```bash
aaPanel 建站 + DB
↓
貼一條 command
↓
網站完成
```

---

## 🧠 一句總結

```text
把「人手流程」變成「可重播腳本」，就是你這個系統的核心價值。
```

---
