# Jofit 自動報名 App

一個 SwiftUI iOS App，搭配一個跑在使用者自己 VPS 上的後端，把課程報名自動化：App 負責瀏覽課表、建立預約、顯示狀態；**實際「算什麼時候該送出、真的送出」這件事由後端負責**，跟手機開不開、App 有沒有被關掉都無關。後端直接對 Google 表單的 `formResponse` 端點送出 POST 請求（不透過 WebView 模擬點擊，速度較快）。

目前串接的表單是 **Jofit 模擬表單**（測試用）。之後要換成正式表單時，打開新表單頁面原始碼搜尋 `entry.`，把 `backend/api/app/google_form.py` 裡的網址與三個 `entry.*` ID 換掉即可（同時更新 `Jofit/Services/BackendClient.swift` 的註解，提醒自己兩邊要一致）。

## 功能

- **首次使用強制設定**：第一次打開 App 會擋一個全螢幕畫面，一定要填完姓名與員工編號才能進入（`Views/OnboardingView.swift`）。
- **課程瀏覽 + 兩層篩選**：課程分頁可以篩「全部顯示／夜間（20:00 後）／非夜間（20:00 前）」，再篩「不顯示哪幾個星期幾」，並可選要看未來 4 週裡的哪幾週（各週會標出實際日期範圍）。
- **預約＝丟給後端排程**：點一堂課就是「預約」——表單規定只能在課程日前 6 天內報名，所以後端會自動算出「課程日前 6 天的早上 8:00」當作送出時間；如果那個時間已經過了（表示課程本來就在 6 天內），就直接馬上送出，不用等。這整個判斷與排程都在後端做，App 只是把「我要預約這堂課」這個意圖送過去。
- **預約紀錄**：紀錄分頁依月份摺疊（點開才展開），已送出的顯示綠色、排程中／送出中的顯示藍色、送出失敗的顯示紅色。
- **送出結果推播**：後端實際送出的那一刻（不管是馬上送出還是排程時間到了才送出），會透過 APNs 推播真的通知到手機告訴你成功或失敗——就算 App 沒開、甚至被滑掉也看得到，因為送出這件事本來就不需要手機在場。
- **首頁小工具**：長按主畫面 →「＋」→ 搜尋「Jofit」加入。當天有已送出的課程就顯示日期＋課程名稱＋運動圖案；沒有就顯示日期＋「今天休息」＋休息圖案。
- **避免重複送出**：同一堂課只會建立一筆預約、只會真正送出一次，細節見下面「避免重複送出」章節。

## 專案結構

```
project.yml                  # XcodeGen 專案定義（.xcodeproj 由 CI 自動產生，不進版控）
courses.json                 # 每週固定課表（依星期幾重複）— App 執行時透過網路抓這個檔案
Shared/WidgetData.swift      # App 和小工具都會編譯進去的共用資料模型（透過 App Group 交換資料）
Jofit/                       # 主 App target
  JofitApp.swift
  PushSupport.swift           # AppDelegate：註冊 APNs device token、前景時也顯示推播橫幅
  Jofit.entitlements          # App Group + Push Notifications 權限
  Models/Course.swift         # Course：某一堂課「這一週實際落在哪一天」的具體版本
  Models/CourseTemplate.swift # CourseTemplate：courses.json 的每週重複樣板 + 換算未來 4 週日期
  Models/Reservation.swift    # Reservation：App 端看到的預約狀態（實際邏輯在後端）
  Services/BackendClient.swift           # 呼叫後端 API（建立/查詢/取消預約、註冊 device token）
  Services/CourseStore.swift             # 從 courses.json 抓課表 + 本地快取 + 換算成未來 4 週的日期
  Services/ReservationStore.swift        # 同步後端狀態、本地快取（離線用）、同步小工具
  Services/UserSettings.swift            # 姓名/員工編號/後端網址/授權金鑰 設定
  Views/                      # 課程／紀錄／設定 三個分頁 + 首次使用引導畫面
JofitWidget/                 # WidgetKit extension target
  JofitWidgetBundle.swift
  JofitWidget.swift           # TimelineProvider + 畫面
  JofitWidget.entitlements    # App Group 權限（要跟主 App 一致才能讀到同一份資料）
  Assets.xcassets             # 運動圖案／休息圖案
backend/                     # 跑在使用者 VPS 上的後端，見下面「後端部署」章節
  api/app/                    # FastAPI：預約的建立、排程、送出表單、APNs 推播
  api/tests/test_reservations.py
  caddy/                      # 自訂 Caddy build（含 DuckDNS DNS 驗證 plugin），負責 HTTPS
  docker-compose.yml
  .env.example
.github/workflows/testflight.yml         # CI：build + 自動上傳 TestFlight
```

## 這台機器沒有 Xcode，怎麼開發？

專案完全靠 **XcodeGen + GitHub Actions** 建置，不需要本機 Mac：

- `project.yml` 是專案的原始定義，`.xcodeproj` 由 CI 執行 `xcodegen generate` 現場產生，所以沒有被加進 git（避免手動維護容易衝突的 pbxproj 檔）。
- 每次 push 到 `main` 且改到 `Jofit/**`、`project.yml` 時，GitHub Actions 會自動在 macOS runner 上編譯、簽署、上傳到 TestFlight。
- 簽章使用 **App Store Connect API Key** 搭配 `xcodebuild -allowProvisioningUpdates`，Apple 會自動在雲端核發/更新憑證與 Provisioning Profile，不需要手動匯入 .p12 憑證或用 fastlane match。

## 一次性設定（在 Apple Developer / App Store Connect 網站上做）

1. **註冊兩個 Bundle ID**：到 [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) 註冊 `com.jofit.autobooking`（主 App）和 `com.jofit.autobooking.widget`（小工具 extension）。如果要改成別的 ID，記得 `project.yml` 裡兩個 target 的 `PRODUCT_BUNDLE_IDENTIFIER` 都要跟著改。
2. **建立 App Group**：同一個 Identifiers 頁面切到 App Groups → 新增一個，ID 填 `group.com.jofit.autobooking`。回到剛剛的兩個 Bundle ID，各自把 App Groups 這項能力打開，並勾選剛建立的這個群組——主 App 和小工具就是靠這個共用容器交換「今天有沒有課」的資料。（自動簽章理論上可以自己建立/更新 App ID 和 Provisioning Profile，但 App Group 這種「能力」本身通常還是要手動建立一次，這步不能省。）
3. **開啟 Push Notifications 能力**：在 `com.jofit.autobooking` 這個 Bundle ID 的 Capabilities 列表勾選「Push Notifications」。這個是單純的能力開關（不像 App Group 需要另外建立資源），自動簽章通常可以自己打開，但如果第一次建置在簽章那步失敗，先來這裡確認有沒有打勾。
4. **建立 App Store Connect 上的 App 紀錄**：App Store Connect → App → 新增 App，Bundle ID 選 `com.jofit.autobooking`（小工具 extension 不用另外建 App 紀錄，它會跟著主 App 一起上傳）。TestFlight 上傳前必須先有這筆紀錄。
5. **建立 App Store Connect API Key**：App Store Connect → Users and Access → Integrations → App Store Connect API → 產生 Key，角色要選 **Admin**（一開始選過 App Manager，結果 `xcodebuild -exportArchive` 在建立 Provisioning Profile 那步報 `Cloud signing permission error`——App Manager 權限不夠讓 CI 自動建立/管理簽署憑證與 Profile，換成 Admin 才過）。下載 `.p8` 檔（只能下載一次，存好）。記下 Key ID 與 Issuer ID。
6. 把 `.p8` 檔轉成 base64：
   - **Mac / Linux**：
     ```bash
     base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
     ```
   - **Windows（PowerShell）**：直接讀檔案原始位元組轉 base64，不要用 `certutil -encode`——它會在頭尾加上 `-----BEGIN CERTIFICATE-----` 這種文字並用 CRLF 換行，很容易忘記清乾淨或清不乾淨，貼進 GitHub Secret 之後解碼出來的 `.p8` 會是壞的（CI 上 `xcodebuild` 會報 `Invalid authentication key credential` 這種不好懂的錯）。用這個指令，結果會直接複製到剪貼簿：
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard
     ```
     複製出來的字串直接貼進 `ASC_API_KEY_BASE64` 這個 Secret，不用再手動處理。
7. **在 GitHub repo 設定 Secrets**（Settings → Secrets and variables → Actions）：

   | Secret 名稱 | 內容 |
   |---|---|
   | `APPLE_TEAM_ID` | Apple Developer 帳號的 Team ID（Membership 頁面可查） |
   | `ASC_API_KEY_ID` | App Store Connect API Key 的 Key ID |
   | `ASC_API_ISSUER_ID` | App Store Connect API 的 Issuer ID |
   | `ASC_API_KEY_BASE64` | 上一步轉出的 base64 字串 |

8. Push 到 `main`（或手動在 Actions 頁面 `workflow_dispatch` 觸發）即可觸發第一次建置。第一次跑因為沒有本機 Mac 測過，簽章/流程如有問題請看 Actions log 除錯（常見問題是 Bundle ID／App Group 未註冊、API Key 權限不足）。
9. 建置成功後幾分鐘內會出現在 TestFlight，用你訂閱的 TestFlight 帳號把自己加為測試者即可安裝到 iPhone，安裝後長按主畫面「＋」搜尋「Jofit」加入小工具。打開 App 後到「設定」分頁填入後端網址與授權金鑰（見下面「後端部署」章節）才能建立預約。

## 更新課程清單

課程清單**不需要改程式碼、不需要出新版 App**。App 每次開啟（以及在課程列表下拉重新整理）都會即時抓取：

```
https://raw.githubusercontent.com/jo1project/jofit.Mark2/main/courses.json
```

`courses.json` 存的是**每週固定重複的課表**（例如「每週一 18:35 Zumba」），不是特定日期，因為健身房的課表本來就是照星期幾每週重複。App 拿到這份清單後，會自動幫每一筆換算出「未來 4 週，每一週各自落在哪一天」——所以完全不用每週手動改日期，只有健身房真的調整了每週課表（新增/刪除/改時段）時才需要改這個檔案：

```json
[
  { "id": "mon-1835-1", "weekday": "週一", "time": "1835", "name": "Zumba" }
]
```

要更新課表，直接編輯 repo 根目錄的 `courses.json`（可以在 GitHub 網頁上點檔案的鉛筆圖示直接改，不用 clone），push 到 `main` 即可，幾秒內下次開 App 或下拉重新整理就會拿到新清單。`weekday` 只接受 `週日` ~ `週六`；`time` 是四位數 24 小時制（`1120` 代表 11:20）；`id` 只要在整份清單裡不重複即可（同一天同時段有多堂課時，用 `id` 尾碼區分，例如 `tue-1820-1`／`tue-1820-2`）。

因為 `courses.json` 不在 `.github/workflows/testflight.yml` 監看的 `Jofit/**`、`project.yml` 路徑內，改這個檔案**不會**觸發 TestFlight 重新建置 —— 這是刻意設計的，課表更新和 App 版本完全脫鉤。

幾個實作細節：
- App 會把抓到的樣板清單存一份在本機（`courses_cache.json`），下次開啟時如果剛好沒網路，會先用上次抓到的快取重新換算日期顯示，並在畫面下方顯示錯誤訊息。
- `Jofit/Models/CourseTemplate.swift` 裡的 `CourseTemplates.fallback` 是全新安裝、且第一次開啟時剛好沒網路（沒有任何快取可用）才會用到的內建預設清單，平常不會用到，只是保底。
- 因為這個 repo 目前是 **public**，`courses.json` 的網址任何人拿得到連結都看得到內容（課程時段/名稱本身不算敏感資料，但如果之後想關閉這個能見度，需要改用其他有存取控制的來源，例如私有的小型 API）。

## 自動送出的可靠度（現在跟「App 被滑掉」完全無關了）

這是升級過的架構：原本是純手機端設計，精準送出依賴 App 開在前景，App 被滑掉（force-quit）就完全沒有背景執行能力，只能靠本機通知提醒你手動打開；**現在這整件事搬到 VPS 上的後端做**（部署方式見下面「後端部署」章節），手機端只剩「顯示狀態」跟「推播通知結果」這兩個角色：

1. 你在 App 裡點一堂課，App 呼叫後端的 `POST /reservations`，把「我要預約這堂課」這個意圖送過去，後端立刻算出送出時間（課程日前 6 天的早上 8:00，或已經在 6 天內就是現在）存進資料庫。
2. 後端有一個每 30 秒醒來一次的排程迴圈（`backend/api/app/scheduler.py`），檢查有沒有預約的送出時間到了，到了就直接對 Google 表單送出 POST——這個過程完全在 VPS 上執行，跟你的手機有沒有開、在不在線上、App 有沒有被滑掉完全無關。
3. 送出完成的那一刻（成功或失敗），後端透過 **APNs** 推播一則真的遠端推播通知到你的手機。這跟本機通知不同：遠端推播是蘋果的伺服器主動送到裝置的系統層級，就算 App 被滑掉，系統一樣會顯示這則推播的橫幅——因為顯示一則通知本來就不需要你的 App process 在跑。
4. App 打開時（以及每 30 秒一次，只要 App 還開著）會呼叫 `GET /reservations` 把最新狀態同步下來，所以就算你錯過了推播，打開 App 也看得到最新狀態。

換句話說：現在你可以選好幾週後的課、完全不管手機，後端到了那天早上該送就會送，推播會通知你結果。少數會受影響的情況只剩「後端本身」的可靠度——VPS 掛了、Docker 沒開機自動啟動、或 Google 表單那邊真的擋掉了——這些跟 iOS 平台限制無關，是一般伺服器維運要注意的事，例如可以額外設定 `docker compose` 的 `restart: unless-stopped`（已經設定了）確保 VPS 重開機後容器會自動起來。

## 避免重複送出（現在整套邏輯都在後端）

Google 表單的 `formResponse` 端點沒有任何「防重複」機制——同樣的內容 POST 兩次，就是兩筆一模一樣的回應紀錄，Google 或負責處理的小編完全看不出來是同一個人手滑點兩次、還是程式邏輯有問題重複送了。既然沒辦法靠對方擋，就只能在後端這邊確保「每筆預約這輩子最多只送出一次」（`backend/api/app/reservations.py`），做法分三層：

1. **同一堂課只會有一筆預約**：`create_reservation()` 一開始就檢查這堂課是不是已經有預約紀錄了，有的話直接回傳既有的那筆；另外資料庫的 `course_id` 欄位有 `UNIQUE` 限制，就算兩個請求剛好同時打進來，也只會有一筆真的寫進去。
2. **送出中的狀態會鎖住，避免被重複挑中**：排程迴圈每 30 秒檢查一次「還在 `pending` 且時間到了」的預約，但如果送出的網路請求還沒回應（例如 Google 那邊比較慢），下一輪檢查理論上又會挑中同一筆。修法是用一個 process 內的 `asyncio.Lock` 包住「把狀態從 `pending` 改成 `submitting`」這一步，這一步是同步的、不用等網路回應——之後的檢查都只挑 `pending` 的預約，`submitting` 的會被跳過。（原本用「資料庫層級的 `UPDATE ... WHERE status='pending'`」想達到同樣效果，本機測試時發現這個假設其實不成立，兩個連線的更新沒有像預期一樣互斥，所以改用程式內的鎖，簡單也更容易驗證是對的。）
3. **送出結果不明時，寧可不送、不要亂猜**：如果後端在等網路回應的當下被中止（例如剛好在重新部署、或容器重啟），下次啟動時這筆預約會卡在 `submitting`——這時候完全不知道剛剛那個 POST 到底送到了沒有。後端不會自動重送（重送有機會造成真的重複），而是直接標成「送出失敗」，並註明「狀態不明，請手動確認」，讓你自己判斷要不要在 App 裡移除重試。這個情境很少見，但既然會影響「有沒有重複報名」，就選擇比較保守的處理方式。

這三層合起來的效果：正常情況下每筆預約保證只送出一次；極端情況下（後端在送出當下被中止）寧可讓你手動確認一次，也不會自動幫你送第二次。這幾個判斷都寫了對應的測試（`backend/api/tests/test_reservations.py`），本機真的跑過確認過（過程中就是靠這個測試抓到上面提到的資料庫鎖沒生效的問題）。

## 小工具的更新時機

`ReservationStore` 每次預約狀態變化（送出成功、失敗、取消）都會把「目前所有已送出的課程」寫進 App Group 共用容器，並呼叫 `WidgetCenter.shared.reloadAllTimelines()` 請求小工具重畫。但 WidgetKit 的更新不是「呼叫了就馬上畫面變」——iOS 會統籌全系統小工具的更新頻率、依電量與使用狀況調整，實際上通常幾秒到幾分鐘內會更新，但沒有精確保證。另外小工具本身也會在跨過午夜時自動換成新一天的內容（timeline 本來就排了今天、明天兩筆），不需要 App 特別做什麼。

圖片的部分：兩張圖是你提供的 Google Drive 連結下載下來直接放進小工具的 Assets.xcassets，運動圖是 1408×768 的 JPEG，休息圖是 32×32 的 PNG（原始檔案本身就是這個尺寸，如果小工具上看起來有點糊，是因為 32×32 被放大顯示，之後想換更高解析度的圖片，直接替換 `JofitWidget/Assets.xcassets/RestDay.imageset` 裡的檔案即可）。

## 後端部署（VPS）

後端跑在你自己的 VPS 上（Docker Compose），已經實際部署並測試過（見下面）。架構：

```
iOS App ──HTTPS(Bearer Token)──▶ Caddy（自訂 build，DuckDNS DNS-01 驗證 HTTPS）──▶ FastAPI（SQLite）
                                                                                      │
                                                                                      ├─ 每 30 秒排程迴圈，到點送出 Google 表單
                                                                                      └─ 送出完成 → APNs 推播結果
```

**為什麼用 DNS 驗證申請 HTTPS，不是常見的 port 80 驗證**：這台 VPS 的 port 80 已經被既有的 AdGuardHome（裝在 snap 裡）佔用，為了完全不去動這個既有服務，改用 DuckDNS 的 DNS-01 challenge——Caddy 只需要 port 443，跟 AdGuardHome 完全不衝突。

### 部署到新環境 / 重新部署

```bash
# 1. 把 backend/ 整個目錄複製到 VPS（例如 /opt/jofit-backend）
scp -r backend/* user@your-vps:/opt/jofit-backend/

# 2. 在 VPS 上，複製 .env.example 成 .env 並填好（見檔案內的說明）
cp .env.example .env

# 3. 如果要開 APNs 推播，把 .p8 金鑰放到 backend/apns_key.p8，
#    並確認 docker-compose.yml 裡 api 服務有掛載 ./apns_key.p8

# 4. 建置並啟動
docker compose up -d --build

# 5. 確認
curl https://<你的 DuckDNS 網域>/health   # 應該回 {"ok":true}
```

之後改了 `backend/` 底下的程式碼，重新部署只要把改動的檔案 `scp` 上去，再跑一次 `docker compose up -d --build`（Compose 會偵測到程式碼變了才重新 build，沒變的話幾乎瞬間完成）。

### 環境變數（`.env`，不會進 git）

| 變數 | 說明 |
|---|---|
| `BEARER_TOKEN` | App 呼叫後端 API 時要帶的授權金鑰，填進 App 的「設定」分頁 |
| `DOMAIN` | DuckDNS 網域，例如 `jofit.duckdns.org` |
| `DUCKDNS_TOKEN` | DuckDNS 帳號頁面上的 token，Caddy 申請憑證用 |
| `APNS_KEY_ID` / `APNS_TEAM_ID` | APNs 金鑰的 Key ID 與 Apple Developer Team ID（不填就自動跳過推播，不會報錯） |
| `APNS_BUNDLE_ID` | 要跟 App 的 Bundle ID 一致（預設 `com.jofit.autobooking`） |
| `APNS_USE_SANDBOX` | TestFlight／上架後的正式建置填 `false`；如果之後改用 Xcode 直接裝到手機的 Debug 建置才需要 `true` |

### 已驗證的部分

- `docker compose up -d --build` 在 VPS 上實際跑過，兩個 container（`api`、`caddy`）都正常啟動。
- HTTPS 是真的 Let's Encrypt 憑證（DNS-01 驗證），用 `openssl s_client` 確認過 issuer 是 Let's Encrypt。
- `/health`、`/reservations`（含驗證失敗回 401）都用公開 HTTPS 網址實際 curl 測試過。
- APNs 金鑰載入、ES256 JWT 簽章都本機測試過（`push._configured()` 回傳 `True`），但**還沒有真的送過一則推播到實體裝置**——這需要 Phase C（iOS App 註冊 device token）跑在真的 iPhone 上才能驗證，目前這個環境沒有 Mac/iPhone，無法完成這一步的驗證。

## 已知未驗證事項

這個環境沒有 Mac，所有 Swift 程式碼與 CI 設定都是照標準寫法產生、未實際跑過 `xcodebuild`。第一次在 GitHub Actions 跑之前，建議先用一個非正式的測試帳號選一堂 6 天內的課（會馬上送出），確認 entry ID 對應正確、且不會誤送到真正要處理報名的表單。

小工具（WidgetKit extension + App Group）跟 Push Notifications 是這個專案裡風險最高的新增部分，原因是它們牽涉多個 target 一起簽章、兩項要手動在 Apple Developer 網站開啟的能力（App Group、Push Notifications），這些步驟本身無法在沒有 Mac 的環境下驗證。如果第一次建置失敗，先看 Actions log 裡是 `Jofit` 這個 target 出錯還是 `JofitWidgetExtension` 出錯：如果是後者，最常見原因是 App Group 沒建好、或兩個 Bundle ID 的 App Groups 能力沒有勾選同一個群組；如果是簽章階段整體失敗，檢查 Push Notifications 能力有沒有在 `com.jofit.autobooking` 上開啟。

Phase C（App 改接後端）目前完成但**完全沒有在真實裝置上跑過**：`BackendClient` 的 HTTP 呼叫、`ReservationDTO` 的日期解析、APNs device token 的註冊流程，這些都是照 API 規格與標準寫法寫的，邏輯上跟後端（已經測過）的回應格式一致，但沒有 Xcode/iPhone 可以實際建置執行來確認。第一次裝上真機後，建議照這個順序驗證：（1）設定分頁填好後端網址與授權金鑰，（2）在課程分頁選一堂 6 天內的課，確認能立刻在「紀錄」分頁看到「已送出」、且手機收到推播；（3）選一堂 6 天以上的課，確認狀態顯示「已排程」且時間正確；（4）到 VPS 上用 `docker compose logs api` 確認後端真的有收到並記錄這筆預約。
