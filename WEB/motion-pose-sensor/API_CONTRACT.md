# Django 接收介面

App 的「Django API 設定」可填入完整的 HTTPS 網址，例如 `https://your-domain.example/api/telemetry/`。依新版 Swift 交接文件，App 也接受私有 IPv4 的 HTTP 網址，例如 `http://172.20.10.2:8000/api/telemetry/`；HTTP 位址限 `10.x.x.x`、`172.16–31.x.x` 或 `192.168.x.x`。開啟傳送後，App 以 `POST` 和 `Content-Type: application/json` 傳送資料。任何 `2xx` 回應都視為成功。未填網址或未開啟傳送時，不會送出資料。

每筆資料有共同欄位：

- `schema_version`：目前為 `1`。
- `device_id`：安裝時產生並保存在該裝置的 UUID，用來分辨 iPhone 與 iPad。
- `device_kind`：`iphone` 或 `ipad`。
- `type`：`motion` 或 `body_pose`。
- `timestamp_ms`：Unix 毫秒時間戳。

三軸模式的範例：

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

如果裝置不支援 ARKit 位置追蹤，`position_m` 可以缺省；如果不支援 Core Motion 姿態追蹤，角度與角速度欄位可以缺省。

關節模式的範例：

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

關節的 `x`、`y` 是旋轉後相機影像中的 2D 正規化座標，範圍為 `0...1`，原點在左下；`confidence` 範圍也是 `0...1`。`image_size_px` 是該影格的寬高，畫面旋轉時會互換。App 只傳送信心值至少 `0.3` 的點。沒有偵測到人體時，`joints` 是空物件。這不是關節的 3D 公尺座標，也不會傳送相機影像。

每種資料最多約每秒傳送 5 筆。上一筆還在傳送時，新的資料會略過，不保證每個取樣都送達。Django 可依 `device_id` 和 `type` 儲存最新資料或寫入資料庫，再由網頁輪詢 API 或 WebSocket 呈現。手機／iPad 的 `localhost` 是裝置本身；可信任的內網測試可用 Mac 的私有 IPv4 HTTP 位址，公開服務則需有效 HTTPS 憑證。正式對外服務前，Django 端仍需加入驗證與權限控管。
