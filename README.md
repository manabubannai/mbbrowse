# mbブラウザ

Brave の「広告・トラッカーを最初から遮断する」体験を、依存ゼロ・Xcode不要で自作した macOS ブラウザ。WebKit(WKWebView)ベース。毎日1アプリシリーズ。

## 特長
- **Shields(🦁)** — 広告・トラッカーの主要ドメインを標準遮断。ツールバーのライオンでオン/オフ。
- **プライベートウィンドウ** — ⌘⇧N。履歴・Cookieを残さない(非永続データストア)。
- **タブ** — ⌘T で追加、⌘W で閉じる。
- **DuckDuckGo 検索** — URLバーにそのまま検索語を入力。
- 署名+公証済み。macOS 14以降 / Apple Silicon。

## 2バージョン
| | 中身 |
|---|---|
| **v1 classic** | 素直なミニブラウザ。タブ + Shields + プライベート。 |
| **v2 pro** | v1 に **ブックマークバー(★で追加・永続化)** と **ページ内検索(⌘F)** を追加。 |

## 使い方
1. zip を展開して `mbブラウザ.app` を「アプリケーション」へ。
2. 起動。URLバーに検索語かURLを入力。
3. 🦁 で広告遮断のオン/オフを切り替え。

## ビルド(自分でやる場合)
```
cd v1-classic && ./build.sh    # または v2-pro
```
Command Line Tools のみで動く(Xcode不要)。

## 遮断リストについて
`mbbrowse.swift` の `Blocklist.domains` に代表的な広告/解析ドメインを列挙。追記すれば遮断対象を増やせる。

---
Brave は Brave Software, Inc. の商標。本アプリは非公式の自作クローンで、Brave とは無関係。
© manabu / MIT License
