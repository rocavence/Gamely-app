# Gamely 計畫書

## 目標

macOS Game Mode 一啟動，就把四個 Hot Corners 暫時設為無動作；遊戲結束後原封不動還原。使用者裝好之後不需要再操作，也不會因為 Gamely 當掉或被強制結束而遺失原本的設定。

## 範圍

- **做**：跟隨系統 Game Mode、強制 App 清單（轉譯層遊戲不會觸發 Game Mode）、手動暫停、狀態與設定視窗、更新提示、六種語言。
- **不做**：改動 Hot Corners 以外的系統設定、掃描執行中的程式猜測遊戲、收集任何資料。

## 架構

| 資料夾 | 職責 |
|---|---|
| `Gamely/Detection` | 從統一記錄（`log stream`）判斷 Game Mode，加上強制 App 偵測，合成「是否該暫停」與原因 |
| `Gamely/HotCorners` | 記住原設定、寫入無動作、還原；Dock 只在狀態真的改變時重啟 |
| `Gamely/Menu`、`Gamely/Settings`、`Gamely/Onboarding` | 選單列、設定卡、第一次使用說明 |
| `Gamely/App` | 進入點、偏好設定、開機啟動、更新檢查、自我測試 |
| `Gamely/DesignSystem` | 字級、間距、顏色、重點色、Reicon 圖示 |

原設定存在 Gamely 自己的偏好設定，只有確認寫回 Dock 之後才清除，所以中途當掉的下一次啟動仍能還原。

## 版本規劃

逐版內容與完成日期見 [ROADMAP.md](../ROADMAP.md)。

| 版本 | 主題 | 狀態 |
|---|---|---|
| 0.2–0.4 | 一定會還原、少打擾、看得懂在做什麼 | 2026-10-11 完成，併入 0.5.0 |
| 0.5 | 新外觀：設計規範、選單列圖示、六種語言、更新提示 | 2026-10-11 完成 |
| 0.9 | 好拿到：Homebrew、六種語言的官網、文件 | 2026-10-11 完成 |
| 1.0 | 0.9 實際使用一段時間、沒有回報問題後發布 | 未開始 |

## 發布流程

1. 改 `project.yml` 的 `MARKETING_VERSION`（新版本）或 `CURRENT_PROJECT_VERSION`（同版本的新建置，關於頁顯示為「版本 b建置號」）。
2. `scripts/selftest.sh` 全部通過。
3. `scripts/build-app.sh --install` 產生 `dist/Gamely-<版本>.zip` 並換掉本機的版本。
4. `gh release create v<版本>`，附上 zip；同版本的新建置改用 `gh release upload --clobber`。
5. `python3 scripts/update-cask.py` 更新 rocavence/homebrew-tap。
6. 官網有改時：`python3 scripts/site/build.py` 產生各語言頁，推上去部署後執行 `python3 scripts/site/indexnow.py`。

## 官網

`docs/index.html`（繁體中文）是原稿。其他語言的文字在 `scripts/site/<語言>.json`，由 `scripts/site/build.py` 產生 `/en/`、`/ja/`、`/ko/`、`/es/`、`/pt/` 五個靜態頁，並一併更新版本號、FAQ 結構化資料與 sitemap。
