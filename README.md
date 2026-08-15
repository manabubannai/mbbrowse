# Mado

圧倒的にシンプルな macOS ブラウザ。WebKit(WKWebView)ベース、依存ゼロ・Xcode不要。毎日1アプリシリーズ。

## 特長
- **ミニマルUI** — ロゴなし・ブランド表示なし。起動すると無地のスタート画面とURLバーだけ。
- **広告・トラッカー遮断** — 主要ドメインを標準遮断。ツールバーの盾アイコンでオン/オフ。
- **テーマ切替** — 表示 > テーマ から「システムに合わせる / ライト / ダーク」。設定は保存される。
- **Chrome拡張(サブセット)** — 展開済み(unpacked)のChrome拡張の content_scripts を注入できる(下記)。
- **プライベートウィンドウ** — ⌘⇧N。履歴・Cookieを残さない(非永続データストア)。
- **タブ** — ⌘T で追加、⌘W で閉じる。URLバーに検索語を入れればそのまま検索。
- 署名+公証済み。macOS 14以降 / Apple Silicon。

## 2バージョン
| | 中身 |
|---|---|
| **Mado (v1 classic)** | 素直なミニブラウザ。タブ + 広告遮断 + プライベート + テーマ + 拡張機能。 |
| **Mado Pro (v2)** | v1 に **ブックマークバー(★で追加・永続化)** と **ページ内検索(⌘F)** を追加。 |

## 使い方
1. zip を展開して `Mado.app`(または `Mado Pro.app`)を「アプリケーション」へ。
2. 起動。URLバーに検索語かURLを入力。
3. 盾アイコンで広告遮断のオン/オフを切り替え。

## Chrome拡張(サブセット)の使い方
1. メニュー「拡張機能 > 拡張機能フォルダを開く」で `~/Library/Application Support/Mado/Extensions/` を開く。
2. そこに **展開済み(unpacked)** のChrome拡張フォルダ(manifest.json 入り)を置く。
3. 「拡張機能 > 拡張機能を再読み込み」→ 次のページ読み込みから適用。

対応範囲:
- manifest.json は **v2 / v3 両対応**。読むのは `content_scripts` のみ(js / css / matches / exclude_matches / run_at / all_frames)。
- matchパターン(`<all_urls>`, `*://*.example.com/*` など)の適合判定つき。

**非対応(限界)**: background / service worker、popup・options ページ、`chrome.*` API 本体(storage・tabs など)は動きません。つまり「特定サイトにJS/CSSを差し込む」タイプの拡張(ダークテーマ化・UI微調整・ユーザースクリプト系)が対象で、それ以外はChrome本体で使ってください。

## ビルド(自分でやる場合)
```
cd v1-classic && ./build.sh    # または v2-pro
```
Command Line Tools のみで動く(Xcode不要)。

## 遮断リストについて
`mbbrowse.swift` の `Blocklist.domains` に代表的な広告/解析ドメインを列挙。追記すれば遮断対象を増やせる。

---
© manabu / MIT License
