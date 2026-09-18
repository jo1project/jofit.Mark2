# Jofit 自動報名 App

一個 SwiftUI iOS App，直接對 Google 表單的 `formResponse` 端點送出 POST 請求來報名課程（不透過 WebView 模擬點擊，速度較快）。

目前串接的表單是 **Jofit 模擬表單**（測試用）。之後要換成正式表單時，打開新表單頁面原始碼搜尋 `entry.`，把 `Jofit/Services/FormSubmissionService.swift` 裡的網址與三個 `entry.*` ID 換掉即可。

## 功能

- **首次使用強制設定**：第一次打開 App 會擋一個全螢幕畫面，一定要填完姓名與員工編號才能進入（`Views/OnboardingView.swift`）。
- **課程瀏覽 + 兩層篩選**：課程分頁可以篩「全部顯示／夜間（20:00 後）／非夜間（20:00 前）」，再篩「不顯示哪幾個星期幾」，並可選要看未來 4 週裡的哪幾週（各週會標出實際日期範圍）。
- **預約＝自動送出排程**：點一堂課就是「預約」——表單規定只能在課程日前 6 天內報名，所以 App 會自動算出「課程日前 6 天的早上 8:00」當作送出時間；如果那個時間已經過了（表示課程本來就在 6 天內），就直接馬上送出，不用等。
- **預約紀錄**：紀錄分頁依月份摺疊（點開才展開），已送出的顯示綠色、還在排程等待送出的顯示藍色、送出失敗的顯示紅色。

## 專案結構

```
project.yml                  # XcodeGen 專案定義（.xcodeproj 由 CI 自動產生，不進版控）
courses.json                 # 每週固定課表（依星期幾重複）— App 執行時透過網路抓這個檔案
Jofit/
  JofitApp.swift
  Models/Course.swift         # Course：某一堂課「這一週實際落在哪一天」的具體版本
  Models/CourseTemplate.swift # CourseTemplate：courses.json 的每週重複樣板 + 換算未來 4 週日期
  Models/Reservation.swift    # Reservation：使用者的預約，含自動送出時間的計算規則
  Services/FormSubmissionService.swift   # 送出表單的網路請求
  Services/CourseStore.swift             # 從 courses.json 抓課表 + 本地快取 + 換算成未來 4 週的日期
  Services/ReservationStore.swift        # 預約的完整生命週期：建立、排程通知、到點送出、本地儲存
  Services/UserSettings.swift            # 姓名/員工編號設定 + 是否已完成首次設定
  Views/                      # 課程／紀錄／設定 三個分頁 + 首次使用引導畫面
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

## 自動送出的可靠度，以及「App 被滑掉」的影響（誠實說明）

App 目前是**純手機端、沒有後端伺服器**的設計，自動送出的原理是：

1. 預約建立時算出「送出時間」（課程日前 6 天的早上 8:00，或如果已經在 6 天內就是現在）。
2. App 在前景時，每秒會檢查一次有沒有預約的送出時間到了（`ReservationStore.processDue`），到了就馬上呼叫網路請求送出。
3. App 每次從背景回到前景（打開 App）時，也會先做一次這個檢查——所以就算送出時間到的時候 App 沒開，只要你之後某個時間點打開 App，會立刻幫你補送，不會漏掉。
4. 每筆預約會另外排一個**本機通知**在送出時間跳出來，提醒你打開 App。

**關鍵限制**：iOS 完全不提供「App 沒在跑的時候，精準在某個時間點自動執行程式碼」這種能力，背景任務（BGTaskScheduler）只是「系統覺得方便的時候」才觸發，不保證準時，更不保證每天都會跑。**如果你把 App 從多工列表往上滑掉（force-quit），iOS 會直接關閉這個 App 的所有背景執行能力，直到你手動再打開它為止**——這是蘋果刻意的系統行為，沒有任何技術手段可以繞過。

本機通知本身**不受這個限制影響**（就算 App 被滑掉，排程過的通知照樣會準時跳出來，因為它是交給系統排程的，不需要 App process 持續存在），但通知只是提醒，**不會自動幫你送出表單**——你還是要點一下通知把 App 打開，那一刻 App 才會真正發送網路請求。

白話講：只要你在送出時間前後有打開一次 App（不用卡到秒，晚個幾十分鐘也沒關係），排程就會生效；如果你完全不理手機、通知也沒點，且中間又把 App 滑掉過，就不會送出。如果之後需要「完全不用碰手機也保證送出」等級的可靠度，就需要另外做一個雲端後端（例如 Firebase）在正確時間幫你送出——那會是一個要另外維護、且需要把姓名/員工編號這類個資存到雲端的獨立專案，目前先不做，有需要再討論。

## 已知未驗證事項

這個環境沒有 Mac，所有 Swift 程式碼與 CI 設定都是照標準寫法產生、未實際跑過 `xcodebuild`。第一次在 GitHub Actions 跑之前，建議先用一個非正式的測試帳號選一堂 6 天內的課（會馬上送出），確認 entry ID 對應正確、且不會誤送到真正要處理報名的表單。
