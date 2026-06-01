# Gamely

macOS Game Mode 一啟動就自動關閉系統 Hot Corners，遊戲結束再自動還原。常駐選單列。

<p align="center">
  <img src="Resources/icon-1024.png" width="160" alt="Gamely icon">
</p>

## 它在做什麼

玩全螢幕遊戲時，滑鼠不小心滑到螢幕角落就觸發 Mission Control / 桌面 / 螢幕保護程式——很掃興。Gamely 是一個常駐選單列的小工具：

- 偵測到 macOS **Game Mode 啟動** → 暫時把四個 **Hot Corners** 設為「無動作」
- Game Mode **結束** → 把你原本的 Hot Corner 設定**原封不動還原**
- 支援**開機自動啟動**
- 全程在背景，只有選單列一個 🎮 圖示

## 運作原理

### 偵測 Game Mode
macOS 沒有公開的 Game Mode API。唯一可靠的訊號是 **unified log**：`gamepolicyd` / `GamePolicyAgent` 在切換時會印出 `Game mode is on, with N user game processes` / `Game mode is off, …`。Gamely 起一個 `log stream` 子程序、用 predicate 過濾這些訊息來判斷開/關（啟動時另用 `log show` 讀最近一次轉換當作初始狀態，兼做崩潰復原）。

> Game Mode 只對**全螢幕**且 `LSApplicationCategoryType` 結尾為 `.games` 的 app 啟用。透過轉譯層跑的 Windows 遊戲（部分 Steam 遊戲）通常不符合，系統就不會開 Game Mode，Gamely 也就不會動作——這是依設計「跟隨 macOS Game Mode」。原生、有正確分類的全螢幕遊戲（例如系統內建的 Chess.app）才會觸發。

### 關閉 / 還原 Hot Corners
Hot Corners 存在 Dock 的偏好設定 `wvous-{tl,tr,bl,br}-corner`。Gamely：

1. 先把你目前的四角設定（含修飾鍵）存到 **Gamely 自己的 defaults**
2. 把四角都設成 `0`（無動作），`killall Dock` 套用——遊戲是全螢幕，Dock 重啟看不見
3. 遊戲結束時寫回原值再 `killall Dock`

原值存在自己的 defaults，所以**就算 Gamely 中途崩潰**，下次啟動偵測到 Game Mode 已結束就會自動還原；結束 app 也會還原。

### 開機自動啟動
用 `SMAppService.mainApp`（macOS 13+）註冊登入項目。

## 安裝

```bash
git clone <repo-url> Gamely
cd Gamely
./Scripts/make-icon.sh     # 產生 app icon（選用）
./Scripts/build-app.sh
open build/Gamely.app
```

只需要 Xcode Command Line Tools。需要 macOS 14+（Game Mode 自 Sonoma 起）。

## 使用

選單列 🎮 圖示：

| 項目 | 說明 |
|---|---|
| Game Mode: … | 目前狀態（Off / On — Hot Corners paused） |
| Pause Hot Corners in Game Mode | 總開關；關掉 Gamely 就不動作 |
| Launch at Login | 開機自動啟動 |
| Restore Hot Corners Now | 手動還原（保險用，僅在暫停中顯示） |
| Quit Gamely | 結束（會先還原 Hot Corners） |

## 技術棧

- **Swift 6** / **AppKit**（純 system framework）
- **`log stream`/`log show`** 監看 unified log 偵測 Game Mode
- **`UserDefaults(suiteName: "com.apple.dock")`** 讀寫 Hot Corner 設定 + `killall Dock`
- **`SMAppService`** 開機自啟
- **Swift Package Manager** + shell script 打 `.app` bundle + ad-hoc codesign
- **`CGContext` + SF Symbol + `iconutil`** 程式化生成 icon

## 專案結構

```
Gamely/
├── Package.swift
├── Sources/
│   └── Gamely/
│       ├── main.swift
│       ├── AppDelegate.swift       # 選單列 + 串接
│       ├── GameModeMonitor.swift   # log-stream 偵測
│       ├── HotCornerController.swift# 存/關/還原 Hot Corners
│       ├── LoginItem.swift          # SMAppService 開機自啟
│       └── Defaults.swift           # 偏好 + 存的原值
├── Resources/                  # Info.plist / AppIcon.icns / icon-1024.png
└── Scripts/                    # build-app.sh / make-icon.{sh,swift}
```

## Debug

`GAMELY_DEBUG=1` 會在選單加一個「Simulate Game Mode」項目，不用真的開遊戲就能測試關閉/還原流程。

## 已知限制

- macOS 14+；主力測試 macOS 26（Tahoe）
- `killall Dock` 在還原時 Dock 會閃一下（遊戲中因全螢幕看不見）
- Game Mode 偵測倚賴系統的 `notify` 名稱，未來 macOS 版本若改名需跟著更新
- Ad-hoc codesign 只能自己用；發佈給別人需 Developer ID + notarization

## 授權

MIT
