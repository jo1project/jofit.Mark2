# 後端架構設計審查與待修復問題清單 (Backend Review & Issues)

本文件彙整了 Jofit 後端系統（FastAPI + aiosqlite + Playwright + APNs + Caddy）的完整架構審查結果。提供給下一位接手的工程師 / Agent 進行具體修改與重構。

---

## 優先級目錄 (Overview)

| 優先級 | 編號 | 問題簡述 | 涉及檔案 |
| :--- | :--- | :--- | :--- |
| **P0 (Critical)** | 1 | 排程器輪詢間隔過大（30s Jitter），搶課延遲過高 | `backend/api/app/scheduler.py` |
| **P0 (Critical)** | 2 | 08:00 多筆預約串行逐一啟動 Playwright，累積嚴重延遲 | `backend/api/app/reservations.py`, `google_form.py` |
| **P0 (Critical)** | 3 | APNs 推播無差別全系統廣播，洩漏他人預約與個資 | `backend/api/app/storage.py`, `reservations.py`, `push.py` |
| **P0 (Critical)** | 4 | 缺乏物件層級存取控制 (IDOR)，可查詢與刪除他人預約 | `backend/api/app/main.py`, `reservations.py` |
| **P0 (Critical)** | 5 | `submission_attempts` 防護缺乏時段維度且失敗後鎖定 6 天（死鎖） | `backend/api/app/reservations.py`, `storage.py` |
| **P1 (High)** | 6 | VPS 規格（961MB RAM）下的 Playwright 記憶體與崩潰風險 | `backend/api/app/google_form.py` |
| **P1 (High)** | 7 | SQLite 未開啟 WAL 模式、缺乏 Busy Timeout 與索引 | `backend/api/app/storage.py` |
| **P1 (High)** | 8 | Google 表單填寫高度脆弱（完全依賴欄位序 `nth`） | `backend/api/app/google_form.py` |
| **P1 (High)** | 9 | Admin PIN 防暴力破解採全域記憶體計數，存在 DoS 風險 | `backend/api/app/auth.py` |
| **P2 (Medium)**| 10 | `CourseIn` 模型缺乏 date 與 time 正則校驗 | `backend/api/app/models.py` |
| **P2 (Medium)**| 11 | 失敗截圖無法由遠端 API 查看，且會被覆蓋 | `backend/api/app/google_form.py`, `main.py` |
| **P2 (Medium)**| 12 | `GET /reservations` 缺乏分頁與時間範圍過濾 | `backend/api/app/reservations.py`, `main.py` |
| **P2 (Medium)**| 13 | APNs HTTP/2 連線未複用 | `backend/api/app/push.py` |

---

## 詳細問題分析與具體修改建議

### 1. 排程器輪詢間隔過大（30 秒 Jitter）
- **檔案**：`backend/api/app/scheduler.py` (`POLL_INTERVAL_SECONDS = 30`)
- **現狀分析**：
  課程在開課前 6 天早上 08:00:00 準時開放報名（`compute_fire_date` 回傳 `08:00:00+08:00`）。但目前排程器迴圈是固定 `await asyncio.sleep(30)`。如果前一次輪詢落在 `07:59:45`，下一次輪詢就在 `08:00:15`，造成高達 15～29 秒的延遲。熱門課程在幾秒內就會秒殺，這會直接導致搶課失敗。
- **修改建議**：
  1. 實作動態休眠：查詢下一筆即將到期的預約時間 `next_fire_date`。
  2. 若距離到期時間大於 30 秒，休眠 `min(gap - 10, 30)` 秒。
  3. 當進入到期前 10 秒（如 07:59:50），切換為精確倒數 `asyncio.sleep(remaining)`，在 08:00:00.000 準時觸發 `process_due()`。

---

### 2. 08:00 到期預約採「串行逐一執行 Playwright」，累積延遲嚴重
- **檔案**：`backend/api/app/reservations.py` (`process_due`)、`backend/api/app/google_form.py`
- **現狀分析**：
  ```python
  for reservation_id in due_ids:
      await _submit(reservation_id)
  ```
  在 08:00，通常有多筆同日開放的預約同時到期（多位員工或多堂課程）。
  目前使用 `for` 迴圈逐筆 `await _submit`，每一筆都需要啟動 Chromium、加載 Google 表單、填表、點擊、等待網路閒置，耗時 3～6 秒。
  若有 5 筆預約：
  - 第 1 筆：08:00:05 送出
  - 第 2 筆：08:00:11 送出
  - 第 5 筆：08:00:30 送出，後面幾筆基本上搶不到名額。
- **修改建議**：
  1. 使用並行處理（例如 `asyncio.gather`），但必須配合 `asyncio.Semaphore` 限制同時執行的數量（例如上限 2 個），以防 1 vCPU / 1GB RAM 的 VPS 記憶體耗盡。
  2. （進階優化）Google Form 實際上只要帶正確的 `fbzx`、`fvv=1`、`pageHistory=0` 及對應的 `entry.XXXX` 欄位，即可用輕量的 `httpx.AsyncClient` 在 50ms 內送出，無需啟動龐大的 Chromium。若能改回 HTTP POST，即可完全消除瀏覽器冷啟動與資源排隊問題。

---

### 3. APNs 推播採全系統廣播，洩漏他人個資與報名動向
- **檔案**：`backend/api/app/storage.py`、`backend/api/app/reservations.py` (`_notify_result`)、`backend/api/app/push.py`
- **現狀分析**：
  `devices` 資料表目前為：
  ```sql
  CREATE TABLE IF NOT EXISTS devices (
    token TEXT PRIMARY KEY,
    registered_at TEXT NOT NULL
  );
  ```
  當任何一筆預約執行完成後，`_notify_result` 會從 `devices` 取出所有 tokens，對每台裝置發送推播：「XXX 已送出」或「XXX 失敗」。
  所有安裝 App 的員工都會收到其他同仁的搶課結果與課程名稱。
- **修改建議**：
  1. 修改 `devices` 表結構，加入 `employee_id TEXT NOT NULL`（或 `PRIMARY KEY (token, employee_id)`）。
  2. 修改 `POST /device-token` API 模型，由前端傳入 `token` 與 `employee_id`。
  3. `_notify_result` 改為只發送給該預約的 `employee_id` 所綁定的裝置（若有 admin 需求可另行標註）。

---

### 4. 缺乏物件層級存取控制 (IDOR) 與資料外洩
- **檔案**：`backend/api/app/main.py`、`backend/api/app/reservations.py`
- **現狀分析**：
  1. `GET /reservations`：直接撈出全表所有預約，前端再用 `settings.employeeID` 過濾。任何拿到 Bearer Token（已寫死在 App 與開源專案中）的人，都能直接查閱全公司同仁姓名、工號與課程預約。
  2. `DELETE /reservations/{reservation_id}`：僅有 `require_auth`，沒有驗證操作者是誰。任何人拿到他人的 `reservation_id` 就能呼叫 DELETE 取消他人的預約。
- **修改建議**：
  1. `GET /reservations` 支援 `employee_id` 查詢參數或 Header；一般使用者僅回傳本人的預約；只有帶 `X-Admin-Pin` 的管理者才能查閱全部。
  2. `DELETE /reservations/{reservation_id}` 需傳入 `employee_id`，SQL 條件加上 `WHERE id = ? AND employee_id = ?`，防止任意刪除他人紀錄（管理員帶 PIN 可豁免）。

---

### 5. `submission_attempts` 安全防護機制的作用域與鎖定時間缺陷
- **檔案**：`backend/api/app/reservations.py`、`backend/api/app/storage.py`
- **現狀分析**：
  ```python
  MAX_ATTEMPTS_PER_WINDOW = 2
  ATTEMPT_WINDOW = timedelta(days=6)
  scope = (row["employee_id"], row["course_date"], row["course_name"])
  ```
  1. **缺少時間維度**：`scope` 只有 `(employee_id, course_date, course_name)`，缺少 `course_time`。若同天有兩堂同名但不同時段/教室的課程，第 2 堂會被 `already_succeeded` 擋下。
  2. **失敗後死鎖 6 天**：若因網路暫時不穩或 Playwright 超時累計失敗 2 次，`ATTEMPT_WINDOW` 設定為 6 天，該員工在接下來 6 天內完全無法重試該課程。即便使用者手動在 App 重新送出，後端仍會直接以 `max_attempts` 擋下。
- **修改建議**：
  1. `submission_attempts` 資料表與查詢 `scope` 補上 `course_time`。
  2. 將失敗嘗試的鎖定視窗由 6 天縮短（例如改為 15~30 分鐘，或允許在有新的手動預約請求時清除舊的 failed 計數）。

---

### 6. VPS 資源限制（961MB RAM, 1 vCPU）下的 Playwright 記憶體與崩潰風險
- **檔案**：`backend/api/app/google_form.py`
- **現狀分析**：
  Chromium 啟動參數包含 `--single-process`（已知在現代 Chromium 中有記憶體洩漏與 crash 問題）。
  每次提交都全新 `chromium.launch()`，尖峰記憶體 ~160MB。若遇併發或記憶體未及時回收，容易被 Linux OOM killer 終止容器。
- **修改建議**：
  1. 移除 `--single-process`。
  2. 評估共用單一 Browser 實例，每次僅開關 `BrowserContext` 或 `Page`，減少每次啟動進程的開銷。
  3. 加入總體逾時保護（`asyncio.wait_for`），避免 Playwright 凍結時卡死整個背景 Task。

---

### 7. SQLite 未啟用 WAL 模式、缺乏 Busy Timeout 與索引
- **檔案**：`backend/api/app/storage.py`
- **現狀分析**：
  預設模式下 SQLite 寫入會鎖住整顆資料庫。併發寫入時容易出現 `sqlite3.OperationalError: database is locked`。
  排程器每 30 秒執行一次 `SELECT ... WHERE status = 'pending' AND fire_date <= ?`，但目前該查詢無索引，屬於全表掃描。
- **修改建議**：
  1. 在 `init_db()` 中加入：
     ```python
     await db.execute("PRAGMA journal_mode = WAL;")
     await db.execute("PRAGMA busy_timeout = 5000;")
     await db.execute("CREATE INDEX IF NOT EXISTS idx_reservations_pending ON reservations(status, fire_date);")
     ```
  2. 在連線時確保 `busy_timeout` 設定生效。

---

### 8. Google 表單填寫高度脆弱（依賴欄位序 `nth`）
- **檔案**：`backend/api/app/google_form.py`
- **現狀分析**：
  表單完全依賴 `nth(0)`, `nth(1)`, `nth(2)`。若表單管理員更改題目順序、新增 Email 收集、或表單選項順序變動，填入資料將完全錯位。
- **修改建議**：
  根據 `aria-label` 或題目標題文字定位 input（如包含「姓名」、「工號」、「課程」），若找不到再退回 `nth` 順序作為備援。

---

### 9. Admin PIN 防暴力破解採全域記憶體計數，存在 DoS 風險
- **檔案**：`backend/api/app/auth.py`
- **現狀分析**：
  `_wrong_pin_times` 是全域共享變數。惡意使用者或誤觸腳本只要連續打錯 5 次 PIN，全系統管理員將被鎖定 15 分鐘無法操作。
- **修改建議**：
  從 Request Header 的 `X-Forwarded-For` 解析來源 IP，將鎖定改為按 IP 追蹤，而非全域鎖定。

---

### 10. 其他次要優化項目
1. **輸入驗證** (`backend/api/app/models.py`)：
   `CourseIn` 的 `date`（應符合 `YYYY-MM-DD`）與 `time`（應符合 `HHmm`）應加入 Pydantic 正則表達式驗證，避免非法輸入導致 500 錯誤。
2. **失敗截圖存取** (`backend/api/app/google_form.py`)：
   截圖檔名可加上 timestamp 或 reservation_id，並提供具備 PIN 驗證的管理員 API 供遠端下載查閱。
3. **歷史資料分頁** (`backend/api/app/reservations.py`)：
   `GET /reservations` 支援 `limit`、`offset` 或日期範圍過濾，避免長期使用後傳輸資料過大。
4. **APNs 連線池** (`backend/api/app/push.py`)：
   使用長生命週期的 `httpx.AsyncClient(http2=True)`，避免每次推播單獨握手連線。
