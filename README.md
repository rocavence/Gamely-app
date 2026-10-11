# Gamely

**繁體中文** · [English](README.en.md)

macOS Game Mode 一啟動就自動關閉系統 Hot Corners，遊戲結束再自動還原。常駐選單列。

<p align="center">
  <img src="scripts/icon/icon-1024.png" width="160" alt="Gamely icon">
</p>

## 它在做什麼

玩全螢幕遊戲時，滑鼠不小心滑到螢幕角落就觸發 Mission Control / 桌面 / 螢幕保護程式——很掃興。Gamely 是一個常駐選單列的小工具：

- 偵測到 macOS **Game Mode 啟動** → 暫時把四個 **Hot Corners** 設為「無動作」
- Game Mode **結束** → 把你原本的 Hot Corner 設定**原封不動還原**；暫停期間你自己改過的角落，以你的新設定為準
- 不會觸發 Game Mode 的遊戲（CrossOver、Whisky、部分 Steam 遊戲）可以加進**強制 App**
- 當機或被強制結束也會還原：下次啟動立刻判斷，沒在玩就還原
- 設定視窗、第一次使用說明、每天檢查一次新版
- 六種語言：繁體中文、English、日本語、한국어、Español、Português
- 全程在背景，只有選單列一個手把圖示

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
brew install --cask rocavence/tap/gamely
```

用 Homebrew 安裝會自動拿掉隔離標記，之後用 `brew upgrade` 更新。或是手動安裝：

從 [Releases](https://github.com/rocavence/Gamely-app/releases/latest) 下載最新的 `Gamely-x.y.z.zip`,解壓後把 **Gamely.app** 拖進「應用程式」。需要 macOS 14+(Game Mode 自 Sonoma 起)。

Gamely 是自簽 app(未經 Apple 公證),第一次打開可能被擋。用 **右鍵 → 打開**,在對話框再按一次「打開」;或終端機執行 `xattr -dr com.apple.quarantine /Applications/Gamely.app`,再打開。

<details><summary>從原始碼自行 build</summary>

```bash
git clone https://github.com/rocavence/Gamely-app.git
cd Gamely-app
brew install xcodegen
./scripts/build-app.sh --install   # 打包 dist/Gamely-<版本>.zip，並裝到「應用程式」
```
需要 Xcode 與 XcodeGen。改圖示：`./scripts/icon/make-icon.sh`。
</details>

## 使用

選單列手把圖示（暫停中會變成實心）：

| 項目 | 說明 |
|---|---|
| 狀態列 | 目前在做什麼、為什麼（遊戲模式、強制 App、手動暫停） |
| 立即暫停熱角／立即還原熱角 | 手動暫停或還原 |
| 遊戲模式時暫停熱角 | 總開關；關掉 Gamely 就不動作 |
| 為應用程式強制啟用遊戲模式 | 強制 App 清單 |
| 登入時啟動 | 開機自動啟動 |
| 設定⋯ | 一般、強制 App、狀態、關於（檢查更新） |
| 結束 Gamely | 結束（會先還原熱角） |

## 技術棧

- **Swift 6** / **AppKit**（純 system framework）
- **`log stream`/`log show`** 監看 unified log 偵測 Game Mode
- **`UserDefaults(suiteName: "com.apple.dock")`** 讀寫 Hot Corner 設定 + `killall Dock`
- **`SMAppService`** 開機自啟
- **XcodeGen** 產生 Xcode 專案、`xcodebuild` 建置；**Swift Testing** 單元測試 + 自我測試
- **`CGContext` + SF Symbol + `iconutil`** 程式化生成 icon

## 專案結構

```
Gamely/
├── project.yml                  # XcodeGen 專案設定（版本號只改這裡）
├── Config/Signing.xcconfig      # 簽章；本機憑證放 Signing.local.xcconfig
├── Gamely/
│   ├── App/                     # 進入點、AppController（串接）、偏好、開機自啟、自我測試
│   ├── Detection/               # Game Mode 記錄解析與監聽、強制 App 偵測、暫停條件
│   ├── HotCorners/              # 存/關/還原 Hot Corners、防抖排程
│   ├── Menu/                    # 選單列
│   ├── Settings/                # 設定視窗（一般、強制 App、狀態、關於）
│   ├── Onboarding/              # 第一次使用說明
│   ├── DesignSystem/            # 字級、間距、圓角、顏色、重點色、Reicon 圖示
│   └── Resources/               # Assets.xcassets、Localizable.xcstrings
├── GamelyTests/                 # 單元測試（Swift Testing）
└── scripts/                     # build-app.sh、selftest.sh、icon/、reicon/（圖示）、l10n/（翻譯表）
```

## 測試

```bash
xcodebuild test -project Gamely.xcodeproj -scheme Gamely   # 單元測試（先跑 xcodegen generate）
./scripts/selftest.sh [項目]                               # 自我測試（項目見腳本開頭）
```
自我測試會實際操作 app 的控制器與選單，但改的是測試用的偏好設定網域，不會重啟 Dock，也不碰你真正的熱角。

## Debug

除錯版（Debug configuration）的選單會多一個「Simulate Game Mode」項目，不用真的開遊戲就能測試關閉/還原流程。

## 已知限制

- macOS 14+；主力測試 macOS 26（Tahoe）
- `killall Dock` 在還原時 Dock 會閃一下（遊戲中因全螢幕看不見）
- Game Mode 偵測倚賴系統的 `notify` 名稱，未來 macOS 版本若改名需跟著更新
- 自簽 build 未經 Apple 公證；下載的副本在清除 quarantine 屬性前會被 Gatekeeper 擋下（見安裝）。要廣泛發佈給別人仍需 Developer ID + notarization

## 授權

MIT
