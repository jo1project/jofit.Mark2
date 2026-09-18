# Jofit 自動報名 App

一個 SwiftUI iOS App，直接對 Google 表單的 `formResponse` 端點送出 POST 請求來報名課程（不透過 WebView 模擬點擊，速度較快）。支援「快速一鍵送出」與「排程在指定時間自動送出」兩種模式。

目前串接的表單是 **Jofit 模擬表單**（測試用）。之後要換成正式表單時，打開新表單頁面原始碼搜尋 `entry.`，把 `Jofit/Services/FormSubmissionService.swift` 裡的網址與三個 `entry.*` ID 換掉即可。

## 專案結構

```
project.yml                  # XcodeGen 專案定義（.xcodeproj 由 CI 自動產生，不進版控）
courses.json                 # 每週固定課表（依星期幾重複）— App 執行時透過網路抓這個檔案
Jofit/
  JofitApp.swift
  Models/Course.swift        # Course：某一堂課「這一週實際落在哪一天」的具體版本
  Models/CourseTemplate.swift # CourseTemplate：courses.json 的每週重複樣板 + 換算日期邏輯
  Models/SubmissionRecord.swift
  Services/FormSubmissionService.swift   # 送出表單的網路請求
  Services/SubmissionStore.swift         # 送出紀錄的本地儲存
  Services/CourseStore.swift             # 從 courses.json 抓課表 + 本地快取 + 換算成本週日期
  Services/ScheduleManager.swift         # 定時搶課邏輯
  Services/UserSettings.swift            # 姓名/員工編號設定
  Views/                      # 四個分頁：快速報名、排程搶課、紀錄、設定
.github/workflows/testflight.yml         # CI：build + 自動上傳 TestFlight
```

## 這台機器沒有 Xcode，怎麼開發？

專案完全靠 **XcodeGen + GitHub Actions** 建置，不需要本機 Mac：

- `project.yml` 是專案的原始定義，`.xcodeproj` 由 CI 執行 `xcodegen generate` 現場產生，所以沒有被加進 git（避免手動維護容易衝突的 pbxproj 檔）。
- 每次 push 到 `main` 且改到 `Jofit/**`、`project.yml` 時，GitHub Actions 會自動在 macOS runner 上編譯、簽署、上傳到 TestFlight。
- 簽章使用 **App Store Connect API Key** 搭配 `xcodebuild -allowProvisioningUpdates`，Apple 會自動在雲端核發/更新憑證與 Provisioning Profile，不需要手動匯入 .p12 憑證或用 fastlane match。

## 一次性設定（在 Apple Developer / App Store Connect 網站上做）

1. **註冊 Bundle ID**：到 [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) 註冊 `com.jofit.autobooking`（或改 `project.yml` 裡的 `PRODUCT_BUNDLE_IDENTIFIER` 換成你想要的）。
2. **建立 App Store Connect 上的 App 紀錄**：App Store Connect → App → 新增 App，Bundle ID 選剛剛註冊的那個。TestFlight 上傳前必須先有這筆紀錄。
3. **建立 App Store Connect API Key**：App Store Connect → Users and Access → Integrations → App Store Connect API → 產生 Key，角色選 **App Manager**。下載 `.p8` 檔（只能下載一次，存好）。記下 Key ID 與 Issuer ID。
4. 把 `.p8` 檔轉成 base64（在 Mac 或任何機器都可以）：
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
   ```
   Windows 上可用：`certutil -encode AuthKey_XXXXXXXXXX.p8 tmp.b64`（再手動去掉頭尾的 `-----BEGIN/END-----` 行）。
5. **在 GitHub repo 設定 Secrets**（Settings → Secrets and variables → Actions）：

   | Secret 名稱 | 內容 |
   |---|---|
   | `APPLE_TEAM_ID` | Apple Developer 帳號的 Team ID（Membership 頁面可查） |
   | `ASC_API_KEY_ID` | App Store Connect API Key 的 Key ID |
   | `ASC_API_ISSUER_ID` | App Store Connect API 的 Issuer ID |
   | `ASC_API_KEY_BASE64` | 上一步轉出的 base64 字串 |

6. Push 到 `main`（或手動在 Actions 頁面 `workflow_dispatch` 觸發）即可觸發第一次建置。第一次跑因為沒有本機 Mac 測過，簽章/流程如有問題請看 Actions log 除錯（常見問題是 Bundle ID 未註冊、API Key 權限不足）。
7. 建置成功後幾分鐘內會出現在 TestFlight，用你訂閱的 TestFlight 帳號把自己加為測試者即可安裝到 iPhone。

## 更新課程清單

課程清單**不需要改程式碼、不需要出新版 App**。App 每次開啟（以及在課程列表下拉重新整理）都會即時抓取：

```
https://raw.githubusercontent.com/jo1project/jofit.Mark2/main/courses.json
```

`courses.json` 存的是**每週固定重複的課表**（例如「每週一 18:35 Zumba」），不是特定日期，因為健身房的課表本來就是照星期幾每週重複。App 拿到這份清單後，會自動幫每一筆算出「這個星期幾、落在本週哪一天」，只顯示落在表單允許預約範圍內（今天起 7 天內）的那一堂課——所以完全不用每週手動改日期，只有健身房真的調整了每週課表（新增/刪除/改時段）時才需要改這個檔案：

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

## 排程搶課的限制（誠實說明）

iOS 為了省電，App 進入背景後系統會暫停計時器，所以**精準倒數只有在 App 開在前景時才保證準時**。排程模式會在開放時間前 2 分鐘跳出本地通知提醒你回到 App；如果 App 被系統中止或你太晚回來，倒數會用實際時鐘重新校正，一回到前景偵測到時間已過就會立刻送出，不會卡住，但沒辦法保證完全不會晚幾秒。目前沒有用 Push Notification 或背景任務去偽裝成「App 沒開也能準時」，因為 iOS 平台本來就無法保證那種精準度。

## 已知未驗證事項

這個環境沒有 Mac，所有 Swift 程式碼與 CI 設定都是照標準寫法產生、未實際跑過 `xcodebuild`。第一次在 GitHub Actions 跑之前，建議先用一個非正式的測試帳號跑一次「快速報名」，確認 entry ID 對應正確、且不會誤送到真正要處理報名的表單。
