# Palworld Dedicated Server Docker

[ENGLISH](README.md) | [日本語](README-JA.md) | [繁體中文](README-ZH-TW.md)

本專案提供 [Palworld](https://www.pocketpair.jp/palworld?lang=en) 多人遊戲用的官方專用伺服器 Docker 映像檔，以及 Docker Compose 範例檔。也請一併參考 Palworld 伺服器指南。

[Introduction | Palworld Server Guide](https://tech.palworldgame.com/)

### 注意事項
發佈的 `compose.yaml` 檔案是範例。請依照你的環境適當修改，並在正式使用前確認存檔資料能正確保存。

另外，不建議在 Windows/macOS 上透過 Docker Desktop 執行，因為磁碟讀寫速度會受到限制。請考慮改用 Steam 方式架設伺服器。

[Requirements | Palworld Server Guide](https://tech.palworldgame.com/getting-started/requirements)

## 官方專用伺服器映像檔

映像檔透過 GitHub Packages 發佈。

[Package palserver](https://github.com/pocketpairjp/palworld-dedicated-server-docker/pkgs/container/palserver)

## Docker Compose
你可以使用 Docker Compose 輕鬆架設專用伺服器。

### 啟動與停止
```shell
# 確認目前資料夾內有 compose.yaml。
> ls
compose.yaml

# 啟動伺服器
> docker compose up -d

# 停止伺服器
> docker compose down

# 查看紀錄
> docker compose logs
```

第一次使用 `docker compose up` 啟動伺服器時，存檔與設定檔會產生在 `./Saved` 底下。

### 伺服器設定

各設定項目的詳細說明，請參考 Palworld 伺服器指南。

[Settings and Operations | Palworld Server Guide](https://tech.palworldgame.com/category/settings-and-operations)

如果要調整玩家人數、連接埠或其他啟動參數，請編輯 `compose.yaml`。

```yaml
services:
    # ... #
    command:
      - -port=8211
      - -useperfthreads
      - -NoAsyncLoadingThread
      - -UseMultithreadForDS
```

如果要調整遊戲平衡、伺服器名稱等設定，請編輯 `./Saved/Config/LinuxServer/PalWorldSettings.ini`。以下是設定伺服器密碼與死亡懲罰後的範例：

```ini
[/Script/Pal.PalGameWorldSettings]
OptionSettings=(ServerPassword="quivern0119",DeathPenalty=None)
```

如果要查看預設設定，請參考映像檔內的 `/pal/Package/DefaultPalWorldSettings.ini`。使用 `docker compose up` 啟動專用伺服器後，可以透過以下指令查看內容。請注意，直接編輯這個檔案不會套用到遊戲內。

```ini
> docker compose exec palworld-server bash -c "cat /pal/Package/DefaultPalWorldSettings.ini"
; This configuration file is a sample of the default server settings.
; Changes to this file will NOT be reflected on the server.
; To change the server settings, modify Pal/Saved/Config/LinuxServer/PalWorldSettings.ini.
[/Script/Pal.PalGameWorldSettings]
OptionSettings=(Difficulty=None // ... //)
```

### 更新專用伺服器

**更新前請務必先備份資料。** 使用 `docker compose down` 停止伺服器，將 `compose.yaml` 中的映像檔標籤更新為對應的遊戲版本，然後使用 `docker compose up -d` 重新啟動。
