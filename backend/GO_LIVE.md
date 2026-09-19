# 正式上線清單（模擬表單 → 正式表單）

現況：後端送到 Jofit **模擬表單**（`backend/api/app/google_form.py` 的 `VIEWFORM_URL`）。

## 1. 先確認正式表單能被自動填寫

`submit_form` 依欄位順序填第 1/2/3 個文字框（姓名、工號、課程），按鈕文字須為 `Submit` 或 `提交`，
送出後要看到成功頁面文字。正式表單若有下列任一項就會失敗：

- 要求登入 Google 帳號（含「限制每人只能回覆一次」）
- 額外欄位、必填題、收集 email（欄位順序錯位）
- 有開放時間限制

用 `backend/api/tests/diagnose_browser.py` 檢查欄位數與按鈕文字。
**注意：這支腳本後半段會真的送出一筆「瀏覽器自動化測試」到表單**，對正式表單跑之前先改成只讀不送。

## 2. 清資料（順序：先清、再換網址）

備份 DB 後，在 VPS 清：

- `reservations`：**必須先於換網址**，否則 pending 的測試預約到時間會真的填進正式表單
- `submission_attempts`：否則測試時成功的紀錄會讓相同員工/日期/時段/課名的正式預約被「已成功」擋下
- 不用清：`devices`（推播 token 仍有效）、`course_templates`（課程清單）
- App 不用處理，重新整理後快取會被後端的空清單覆蓋

## 3. 換網址並部署

- 改 `google_form.py` 與 `tests/diagnose_browser.py` 的 `VIEWFORM_URL`
- 部署：VPS `/opt/jofit-backend`（非 git repo）以 rsync 同步 `backend/api/`，再 `docker compose up -d --build api`
- 選擇避開 08:00 搶課時段切換

## 可選

`VIEWFORM_URL` 改讀環境變數（放 VPS `.env`），之後換表單只要改設定再重啟。
