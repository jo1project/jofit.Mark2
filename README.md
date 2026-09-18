# Jofit 自動報名 App

一個 SwiftUI iOS App，直接對 Google 表單的 `formResponse` 端點送出 POST 請求來報名課程（不透過 WebView 模擬點擊，速度較快）。

目前串接的表單是 **Jofit 模擬表單**（測試用）。之後要換成正式表單時，打開新表單頁面原始碼搜尋 `entry.`，把 `Jofit/Services/FormSubmissionService.swift` 裡的網址與三個 `entry.*` ID 換掉即可。

## 功能

- **首次使用強制設定**：第一次打開 App 會擋一個全螢幕畫面，一定要填完姓名與員工編號才能進入（`Views/OnboardingView.swift`）。
- **課程瀏覽 + 兩層篩選**：課程分頁可以篩「全部顯示／夜間（20:00 後）／非夜間（20:00 前）」，再篩「不顯示哪幾個星期幾」，並可選要看未來 4 週裡的哪幾週（各週會標出實際日期範圍）。
- **預約＝自動送出排程**：點一堂課就是「預約」——表單規定只能在課程日前 6 天內報名，所以 App 會自動算出「課程日前 6 天的早上 8:00」當作送出時間；如果那個時間已經過了（表示課程本來就在 6 天內），就直接馬上送出，不用等。
- **預約紀錄**：紀錄分頁依月份摺疊（點開才展開），已送出的顯示綠色、排程中／送出中的顯示藍色、送出失敗的顯示紅色。
- **送出結果通知**：預約實際送出的當下（不管是馬上送出還是排程時間到了才送出），會立刻跳一則本機通知告訴你成功或失敗，不用一直開著 App 盯著看。
- **首頁小工具**：長按主畫面 →「＋」→ 搜尋「Jofit」加入。當天有已送出的課程就顯示日期＋課程名稱＋運動圖案；沒有就顯示日期＋「今天休息」＋休息圖案。
- **避免重複送出**：同一堂課只會建立一筆預約、只會真正送出一次，細節見下面「避免重複送出」章節。

## 專案結構

```
project.yml                  # XcodeGen 專案定義（.xcodeproj 由 CI 自動產生，不進版控）
courses.json                 # 每週固定課表（依星期幾重複）— App 執行時透過網路抓這個檔案
Shared/WidgetData.swift      # App 和小工具都會編譯進去的共用資料模型（透過 App Group 交換資料）
Jofit/                       # 主 App target
  JofitApp.swift
  Jofit.entitlements          # App Group 權限
  Models/Course.swift         # Course：某一堂課「這一週實際落在哪一天」的具體版本
  Models/CourseTemplate.swift # CourseTemplate：courses.json 的每週重複樣板 + 換算未來 4 週日期
  Models/Reservation.swift    # Reservation：使用者的預約，含自動送出時間的計算規則
  Services/FormSubmissionService.swift   # 送出表單的網路請求
  Services/CourseStore.swift             # 從 courses.json 抓課表 + 本地快取 + 換算成未來 4 週的日期
  Services/ReservationStore.swift        # 預約的完整生命週期：建立、排程通知、到點送出、防重複送出、同步小工具
  Services/UserSettings.swift            # 姓名/員工編號設定 + 是否已完成首次設定
  Views/                      # 課程／紀錄／設定 三個分頁 + 首次使用引導畫面
JofitWidget/                 # WidgetKit extension target
  JofitWidgetBundle.swift
  JofitWidget.swift           # TimelineProvider + 畫面
  JofitWidget.entitlements    # App Group 權限（要跟主 App 一致才能讀到同一份資料）
  Assets.xcassets             # 運動圖案／休息圖案
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
3. **建立 App Store Connect 上的 App 紀錄**：App Store Connect → App → 新增 App，Bundle ID 選 `com.jofit.autobooking`（小工具 extension 不用另外建 App 紀錄，它會跟著主 App 一起上傳）。TestFlight 上傳前必須先有這筆紀錄。
4. **建立 App Store Connect API Key**：App Store Connect → Users and Access → Integrations → App Store Connect API → 產生 Key，角色選 **App Manager**。下載 `.p8` 檔（只能下載一次，存好）。記下 Key ID 與 Issuer ID。
5. 把 `.p8` 檔轉成 base64（在 Mac 或任何機器都可以）：
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
   ```
   Windows 上可用：`certutil -encode AuthKey_XXXXXXXXXX.p8 tmp.b64`（再手動去掉頭尾的 `-----BEGIN/END-----` 行）。
6. **在 GitHub repo 設定 Secrets**（Settings → Secrets and variables → Actions）：

   | Secret 名稱 | 內容 |
   |---|---|
   | `APPLE_TEAM_ID` | Apple Developer 帳號的 Team ID（Membership 頁面可查） |
   | `ASC_API_KEY_ID` | App Store Connect API Key 的 Key ID |
   | `ASC_API_ISSUER_ID` | App Store Connect API 的 Issuer ID |
   | `ASC_API_KEY_BASE64` | 上一步轉出的 base64 字串 |

7. Push 到 `main`（或手動在 Actions 頁面 `workflow_dispatch` 觸發）即可觸發第一次建置。第一次跑因為沒有本機 Mac 測過，簽章/流程如有問題請看 Actions log 除錯（常見問題是 Bundle ID／App Group 未註冊、API Key 權限不足）。
8. 建置成功後幾分鐘內會出現在 TestFlight，用你訂閱的 TestFlight 帳號把自己加為測試者即可安裝到 iPhone，安裝後長按主畫面「＋」搜尋「Jofit」加入小工具。

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
4. 每筆預約會另外排一個**本機通知**在送出時間跳出來，提醒你打開 App；真正送出完成的那一刻（不管成功或失敗）也會立刻再跳一則本機通知告訴你結果。這兩則都是 iOS 的本機通知（`UNUserNotificationCenter`），不是要連 APNs 伺服器的遠端推播——因為目前沒有後端，也就沒有伺服器可以主動觸發遠端推播；如果之後真的需要遠端推播（例如伺服器主動通知），那也會跟著需要後端一起做。

**關鍵限制**：iOS 完全不提供「App 沒在跑的時候，精準在某個時間點自動執行程式碼」這種能力，背景任務（BGTaskScheduler）只是「系統覺得方便的時候」才觸發，不保證準時，更不保證每天都會跑。**如果你把 App 從多工列表往上滑掉（force-quit），iOS 會直接關閉這個 App 的所有背景執行能力，直到你手動再打開它為止**——這是蘋果刻意的系統行為，沒有任何技術手段可以繞過。

本機通知本身**不受這個限制影響**（就算 App 被滑掉，排程過的通知照樣會準時跳出來，因為它是交給系統排程的，不需要 App process 持續存在），但通知只是提醒，**不會自動幫你送出表單**——你還是要點一下通知把 App 打開，那一刻 App 才會真正發送網路請求。

白話講：只要你在送出時間前後有打開一次 App（不用卡到秒，晚個幾十分鐘也沒關係），排程就會生效；如果你完全不理手機、通知也沒點，且中間又把 App 滑掉過，就不會送出。如果之後需要「完全不用碰手機也保證送出」等級的可靠度，就需要另外做一個雲端後端（例如 Firebase）在正確時間幫你送出——那會是一個要另外維護、且需要把姓名/員工編號這類個資存到雲端的獨立專案，目前先不做，有需要再討論。

## 避免重複送出（誠實說明怎麼做、怎麼記錄）

Google 表單的 `formResponse` 端點沒有任何「防重複」機制——同樣的內容 POST 兩次，就是兩筆一模一樣的回應紀錄，Google 或負責處理的小編完全看不出來是同一個人手滑點兩次、還是 App 邏輯有問題重複送了。既然沒辦法靠對方擋，就只能在 App 這邊確保「每筆預約這輩子最多只送出一次」，做法分三層：

1. **同一堂課只會有一筆預約**：`ReservationStore.reserve()` 一開始就檢查這堂課是不是已經有預約紀錄了，有的話直接回傳既有的那筆，不會再建一筆新的——所以就算使用者手滑連續點同一堂課好幾下，也只會產生一筆預約。
2. **送出中的狀態會鎖住，避免被重複挑中**：原本的設計是「預約狀態是 `pending`（排程中）」→「時間到就送出」，但 App 有好幾個時機都可能觸發檢查（每秒一次的前景檢查、回到前景時的檢查），如果送出的網路請求還沒回應（例如訊號不好，等了 1–2 秒），下一次檢查照理說又會挑中同一筆「還是 pending」的預約，變成同時送出兩次。修法是：只要一開始要送出，就馬上把狀態改成 `submitting`（送出中）並存檔，這一步是同步的、不用等網路——之後所有檢查都只挑 `pending` 的預約，`submitting` 的會被跳過，所以同一筆不會被兩個檢查同時抓到。
3. **送出結果不明時，寧可不送、不要亂猜**：如果 App 在等網路回應的當下被系統砍掉（例如記憶體不足），下次打開 App 時，這筆預約會卡在 `submitting`——這時候完全不知道剛剛那個 POST 到底送到了沒有。這時 App 不會自動重送（重送有機會造成真的重複），而是直接標成「送出失敗」，並註明「狀態不明，請手動確認」，紅字顯示、要你自己確認並決定要不要在課程分頁移除重試。這個情境非常少見（需要剛好在等網路回應的那 1 秒內被系統砍掉），但既然會影響「有沒有重複報名」，就選擇比較保守的處理方式。

這三層合起來的效果：正常情況下每筆預約保證只送出一次；極端情況下（App 在送出當下被砍）寧可讓你手動確認一次，也不會自動幫你送第二次。

## 小工具的更新時機

`ReservationStore` 每次預約狀態變化（送出成功、失敗、取消）都會把「目前所有已送出的課程」寫進 App Group 共用容器，並呼叫 `WidgetCenter.shared.reloadAllTimelines()` 請求小工具重畫。但 WidgetKit 的更新不是「呼叫了就馬上畫面變」——iOS 會統籌全系統小工具的更新頻率、依電量與使用狀況調整，實際上通常幾秒到幾分鐘內會更新，但沒有精確保證。另外小工具本身也會在跨過午夜時自動換成新一天的內容（timeline 本來就排了今天、明天兩筆），不需要 App 特別做什麼。

圖片的部分：兩張圖是你提供的 Google Drive 連結下載下來直接放進小工具的 Assets.xcassets，運動圖是 1408×768 的 JPEG，休息圖是 32×32 的 PNG（原始檔案本身就是這個尺寸，如果小工具上看起來有點糊，是因為 32×32 被放大顯示，之後想換更高解析度的圖片，直接替換 `JofitWidget/Assets.xcassets/RestDay.imageset` 裡的檔案即可）。

## 已知未驗證事項

這個環境沒有 Mac，所有 Swift 程式碼與 CI 設定都是照標準寫法產生、未實際跑過 `xcodebuild`。第一次在 GitHub Actions 跑之前，建議先用一個非正式的測試帳號選一堂 6 天內的課（會馬上送出），確認 entry ID 對應正確、且不會誤送到真正要處理報名的表單。

小工具（WidgetKit extension + App Group）是這個專案裡風險最高的新增部分，原因是它牽涉兩個 target 一起簽章、一個要手動在 Apple Developer 網站建立的 App Group，這些步驟本身無法在沒有 Mac 的環境下驗證。如果第一次建置失敗，先看 Actions log 裡是 `Jofit` 這個 target 出錯還是 `JofitWidgetExtension` 出錯：如果是後者，最常見原因是 App Group 沒建好、或兩個 Bundle ID 的 App Groups 能力沒有勾選同一個群組。
