# Swift App → Django／Web 交接文件

這份文件可以單獨複製到 Django 專案資料夾，供另一個 Codex 工作階段閱讀；不需要同時開啟 Swift 專案。以下內容依目前 Swift App 的實際傳送程式碼整理。

## 給 Django 專案 Codex 的任務

請閱讀本文件，直接在**目前的 Django 專案資料夾**實作接收 API 與網頁儀表板，不要只提出計畫或範例。如果資料夾尚無 Django 專案，請建立一個。完成 models、migration、views、路由、網頁、必要測試與啟動說明，執行測試並修正失敗。不要假設可以讀取或修改另一個資料夾裡的 Swift 專案。

1. 建立 `POST /api/telemetry/`，接收下述 `schema_version = 1` 的 JSON，驗證欄位後持久化。成功回任何 `2xx` JSON；無效資料回 `400` JSON，並指出錯誤欄位。此端點是原生 App 呼叫，不能要求瀏覽器 CSRF cookie。
2. 提供裝置列表、每台裝置的最新資料及依時間查詢歷史資料的讀取 API。以 `device_id`、`type`、`timestamp_ms` 支援查詢與索引。歷史資料要能限制時間範圍和回傳筆數，避免圖表一次載入全部紀錄。
3. 做一個可用的網頁儀表板：選裝置與時間範圍、顯示最後收件時間；分別畫位置 X/Y/Z（m）、roll/pitch/yaw（度）、角速度 X/Y/Z（度／秒）的時間序列。每 1–2 秒輪詢即可。
4. 顯示 iPad 的最新 2D 人體關節點與骨架。用下述座標系轉換 Y 軸，保持影像長寬比；`joints` 為空時清掉舊骨架。沒有相機照片可作背景，可用空白畫布。不要把 2D 正規化座標當成 3D 公尺座標。
5. 加入對有效／無效 `motion`、缺少可選欄位、空 `joints`、裝置隔離及歷史查詢的測試。提供一份 README，說明安裝、migration、啟動、測試、測試 POST 指令及讓實體 iPhone／iPad 連線的方法。

目前 Swift App **沒有**驗證 token 或 API key 欄位；請先讓開發環境中的現有請求可用。若要把服務公開部署，須加入驗證與權限控管，並清楚標明需要在 Swift App 同步增加的 header／設定；不要假裝現有 App 已會傳 token。不要把密鑰寫死。網頁與 API 若同源，無須為了原生 App 開放寬鬆的 CORS。

## Swift App 現況

- App 支援 iPhone 與 iPad，畫面可手動切換「三軸數值」和「身體關節」。預設 iPhone 為三軸、iPad 為關節，但**不要**在伺服器硬性規定 `iphone` 只能送 `motion` 或 `ipad` 只能送 `body_pose`。
- 使用者在 App「Django API 設定」填入完整的 API URL，例如公開 HTTPS 的 `https://example.com/api/telemetry/`，或手機熱點內 Mac 的私人 IPv4 HTTP 網址 `http://172.20.10.2:8000/api/telemetry/`，再開啟「傳送數值到 Django」。HTTP 僅接受 `10.x.x.x`、`172.16–31.x.x` 或 `192.168.x.x`；公開網域仍須 HTTPS。網址保存在裝置的 `UserDefaults`；傳送開關預設關閉。
- 使用 `POST`，`Content-Type: application/json`、`Accept: application/json`；沒有其他自訂 header。Swift 將資料以 snake_case 編碼。任何 HTTP `2xx` 都視為成功；非 `2xx` 只會在 App 顯示通用錯誤。
- 每種 `type` 最多約 5 筆／秒；上一筆同種類請求未完成時會略過新資料。這是即時取樣，不保證無缺漏。
- `timestamp_ms` 是 App 建立事件時的 Unix 毫秒時間戳。`device_id` 是該安裝產生並保存在 `UserDefaults` 的 UUID 字串；重裝後可能改變。`device_kind` 由裝置類型決定，值為 `iphone` 或 `ipad`。
- 切換模式、暫停或 App 不在前景時，對應感測器會停止；已儲存的歷史資料不應因此消失。

## 共通 JSON 欄位

| 欄位 | 型別 | 說明 |
| --- | --- | --- |
| `schema_version` | integer | 目前固定為 `1` |
| `device_id` | string | 裝置安裝識別 UUID |
| `device_kind` | string | `iphone` 或 `ipad` |
| `type` | string | `motion` 或 `body_pose` |
| `timestamp_ms` | integer | Unix epoch 毫秒；圖表時間軸請依此欄位 |
| `motion` | object | 僅 `type = motion` 時提供 |
| `body_pose` | object | 僅 `type = body_pose` 時提供 |

Swift 的可選欄位通常會從 JSON **省略**，不是送 `null`。請接收下列有效資料型態。

### 三軸位置、角度、角速度

```json
{
  "schema_version": 1,
  "device_id": "A4EDB664-7198-4C7E-901B-056D57BB593B",
  "device_kind": "iphone",
  "type": "motion",
  "timestamp_ms": 1790668800123,
  "motion": {
    "position_m": {"x": 0.12, "y": 0.35, "z": -0.04},
    "attitude_deg": {"roll": 2.1, "pitch": -8.5, "yaw": 12.3},
    "angular_velocity_deg_s": {"x": 0.4, "y": -1.7, "z": 0.2}
  }
}
```

- `position_m` 來自 ARKit `ARWorldTrackingConfiguration`，是**相對於此次追蹤起點／使用者重新設原點後的位置**，單位公尺。Y 軸朝上為正；拿起手機，Y 通常增加。它不是 GPS 或絕對室內座標，追蹤可能漂移。使用者重新設原點或重新啟動追蹤後，數值會跳回接近 0；圖表不要把不同追蹤階段誤解為一條連續的絕對路徑。
- `attitude_deg` 是 Core Motion 的 roll、pitch、yaw，單位度；姿態使用 `.xArbitraryZVertical` 參考系，yaw **不是**羅盤的絕對方位。
- `angular_velocity_deg_s` 是繞裝置 X/Y/Z 軸的當下旋轉角速度，單位度／秒。
- 若裝置不支援 ARKit，`position_m` 可能省略；若無 Core Motion 姿態，`attitude_deg` 和 `angular_velocity_deg_s` 可能省略。App 只在至少有位置或姿態資料時送 `motion`。資料庫與圖表要能處理缺值，不應以 0 冒充。

### 2D 人體關節點

```json
{
  "schema_version": 1,
  "device_id": "5B477491-5CB8-4601-8960-66052E099AA5",
  "device_kind": "ipad",
  "type": "body_pose",
  "timestamp_ms": 1790668800123,
  "body_pose": {
    "coordinate_system": "normalized_image_bottom_left",
    "image_size_px": {"width": 1280, "height": 720},
    "joints": {
      "VNHumanBodyPoseObservationJointNameLeftShoulder": {
        "x": 0.42,
        "y": 0.71,
        "confidence": 0.93
      }
    }
  }
}
```

- 使用 iPad 後置相機與 Apple Vision 取得主要人體的 2D 關節點。關節名稱是 Vision 的原始字串，例如 `VNHumanBodyPoseObservationJointNameLeftShoulder`；請保留原字串，不要依畫面上的翻譯名稱做 API key。
- `x`、`y` 是相機影像中的正規化座標，範圍 `0...1`；原點在**左下**。`confidence` 也是 `0...1`。App 已篩掉信心值小於 `0.3` 的點。
- `image_size_px` 是影格寬高；相機隨 iPad 介面方向旋轉，影格尺寸可能跟著互換。若影格尚未取得或擷取失敗，`image_size_px` 可能省略。
- 沒有人體時 `joints` 是 `{}`。不要沿用上一影格的骨架。若用瀏覽器 Canvas／SVG 畫點，畫布左上為原點，通常需用 `screenY = (1 - y) * drawnImageHeight + offsetY`；X 對應 `x * drawnImageWidth + offsetX`。可按 `image_size_px` 比例排版；沒有尺寸時使用固定比例或正方形畫布。
- App **不會上傳照片或影片**。網頁只需在空白背景繪製點、骨架及可選的名稱／信心值。
- 可連接的主要骨架邊包含：頸部—左右肩、肩—肘—腕、肩—髖、左右髖相連、髖—膝—踝。只在兩端點都存在時畫線。

## 網路與部署注意

App 上填 `localhost` 會指向手機／iPad 本機，**不會**指向開發電腦。若使用手機熱點內網，請讓 Mac 和 iPad 連到該熱點，在 Mac 執行 `python manage.py runserver 0.0.0.0:8000`，查出 Mac 的熱點 IP，並將該 IP 加入 Django `ALLOWED_HOSTS`。先用 iPad 和 iPhone Safari 測試 `http://Mac的IP:8000/dashboard/`，再於 App 填 `http://Mac的IP:8000/api/telemetry/`。Mac 防火牆須允許連線。若熱點阻擋裝置互連，改用其他區域網路或 HTTPS tunnel。內網 HTTP 沒有 TLS 加密，只適合可信任的熱點測試。公開網路須使用有效 HTTPS 憑證與驗證。Django 收到 POST 後，網頁可以輪詢同一套服務的讀取 API；不必讓瀏覽器直接連手機。

本文件描述**目前的資料契約**，不是已存在的 Django 實作。Django 程式碼、資料庫表、讀取 API 與網頁都需要在另一個資料夾建立。
