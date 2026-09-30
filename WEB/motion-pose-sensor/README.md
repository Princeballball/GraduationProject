# iPhone / iPad Telemetry Django 伺服器

此目錄目前沒有 Swift 專案原始碼。伺服器依 [API_CONTRACT.md](API_CONTRACT.md) 與新版 [DJANGO_WEB_HANDOFF copy.md](DJANGO_WEB_HANDOFF%20copy.md) 記錄的 App 實際 JSON 格式實作；Swift 的 `TelemetryClient.swift` 不在此目錄，沒有對它做任何修改。

## 安裝與啟動

需要 Python 3.10 以上。從專案根目錄執行：

```sh
python3 -m venv venv
venv/bin/python -m pip install -r server/requirements.txt
venv/bin/python server/manage.py migrate
venv/bin/python server/manage.py runserver 127.0.0.1:8000
```

瀏覽器開啟 `http://127.0.0.1:8000/`（會導向 `/dashboard/`）。「畫面 1」和「畫面 2」各自選即時設備及顯示內容，可同時看兩台設備，例如手機三軸數值與平板人體關節點；畫面 2 可選「不顯示」。預設依最近資料選 iPhone 的三軸及 iPad 的關節。每個畫面各有連線狀態，頁面每 1.5 秒輪詢。按「暫停畫面」可停止輪詢及繪圖，按「繼續即時」恢復；暫停不會阻止後端接收 App 資料。最後收件時間以伺服器實際收到資料的時間計算，10 秒內有新資料顯示「連線中」。圖表以 App 的 `timestamp_ms` 作時間軸，每台最多取所選範圍內最近 2,000 筆 motion。缺少的欄位不會顯示成 0。骨架只有 2D 點和線，不含相機影像；最新 `joints` 為 `{}` 時會清空。

測試與模型檢查：

```sh
venv/bin/python server/manage.py test telemetry
venv/bin/python server/manage.py check
```

資料預設存在 `server/db.sqlite3`。Migration 位於 `server/telemetry/migrations/`。

## API

| 方法與路徑 | 用途 |
| --- | --- |
| `POST /api/telemetry/` | 接收 `schema_version: 1` 的 `motion` 或 `body_pose` JSON；成功回 `201`，錯誤回 `{"error":{"field":"...","message":"..."}}` 與 `400` |
| `GET /api/devices/` | 裝置列表、最後收件時間及各裝置的 `available_types` |
| `GET /api/devices/<device_id>/latest/` | 該裝置各類型最新一筆；尚無資料的類型為 `null` |
| `GET /api/devices/<device_id>/history/?start_ms=...&end_ms=...&type=motion&limit=1000` | 含兩端點的 Unix 毫秒範圍；`type` 預設 `motion`，`limit` 預設 1000、上限 2000；回傳所選範圍內最近的筆數，按時間升序排列 |

`device_id` 支援大寫或小寫 UUID。`motion.position_m`、`attitude_deg`、`angular_velocity_deg_s` 可依裝置能力省略，但必須至少有位置或姿態；已提供的三軸物件須包含全部對應軸。`body_pose.image_size_px` 可省略，`joints` 可為空物件。錯誤 JSON 會指出欄位。原生 App 的 POST 不需要 CSRF cookie。

`POST /api/telemetry`（沒有尾端 `/`）也直接接收相同資料；App 設定建議使用上表的 `/api/telemetry/` 格式。

在另一個終端送一筆即時測試資料：

```sh
NOW_MS=$(($(date +%s) * 1000))
curl -i http://127.0.0.1:8000/api/telemetry/ \
  -H 'Content-Type: application/json' \
  -d "{\"schema_version\":1,\"device_id\":\"A4EDB664-7198-4C7E-901B-056D57BB593B\",\"device_kind\":\"iphone\",\"type\":\"motion\",\"timestamp_ms\":$NOW_MS,\"motion\":{\"position_m\":{\"x\":0.12,\"y\":0.35,\"z\":-0.04},\"attitude_deg\":{\"roll\":2.1,\"pitch\":-8.5,\"yaw\":12.3},\"angular_velocity_deg_s\":{\"x\":0.4,\"y\":-1.7,\"z\":0.2}}"
```

查詢該筆資料：

```sh
curl 'http://127.0.0.1:8000/api/devices/A4EDB664-7198-4C7E-901B-056D57BB593B/latest/'
```

## iPhone / iPad 連線網址

新版交接文件指出，App 在私有 IPv4 網路可使用 HTTP。這台 Mac 目前的熱點 IP 是 `172.20.10.2`。讓 Mac 和 iPad 連到同一熱點，然後在 Mac 的 `server/` 目錄啟動：

```sh
python manage.py runserver 0.0.0.0:8000
```

先在 iPad Safari 開啟 `http://172.20.10.2:8000/dashboard/`。若能看到儀表板，再於 App「Django API 設定」填以下完整接收網址，並開啟「傳送數值到 Django」：

```text
http://172.20.10.2:8000/api/telemetry/
```

Mac 防火牆須允許連線。若 IP 改變，可用 `ipconfig getifaddr en0` 查詢，再用 `export DJANGO_ALLOWED_HOSTS='localhost,127.0.0.1,新的IP'` 設定並重啟 Django。`127.x.x.x` 和 `localhost` 指向裝置自己；`0.0.0.0` 只用於 Django 監聽，不是平板要填的位址。HTTP 僅適合可信任的私有網路測試。公開網域仍須使用有效 HTTPS，格式是 `https://你的可連線網域/api/telemetry/`，並將網域加入 `DJANGO_ALLOWED_HOSTS`。

現有 Swift App **沒有 API key 或 token 設定與 header**，本機開發端點直接接收目前的 POST。此設定只適合受信任的開發網路；不要將未驗證的寫入 API 直接公開。正式對外部署前，須在 App 增加可設定的密鑰與請求 header，並在伺服器實作對應驗證和讀取權限；密鑰應由環境或安全設定提供，不應寫死。正式 Django 設定至少須提供 `DJANGO_DEBUG=0`、`DJANGO_SECRET_KEY` 及 `DJANGO_ALLOWED_HOSTS`，並使用適當的正式 HTTP 伺服器與 HTTPS 代理。
