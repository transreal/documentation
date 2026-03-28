# Documentation` API リファレンス

パッケージ: `Documentation`
依存: `NBAccess``, `ClaudeCode``
用途: アウトラインプロセッサ拡張。アイデア → パラグラフ展開、翻訳、同期、Markdown/LaTeX エクスポート。

## 公開関数

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストを LLM でパラグラフに展開する。
元アイデアは TaggingRules に保存。パラグラフ表示中は展開不可。
→ Null（非同期実行）または $Failed
Options: Fallback -> False (True でフォールバックモデル使用)

例: `DocExpandIdea[EvaluationNotebook[], 3, Fallback -> True]`

### DocToggleView[nb, cellIdx] → Null | String | $Failed
セルのアイデア ↔ パラグラフ ↔ 翻訳の表示を循環切替する。
現在表示中の内容（編集済みでも）を保存してから切り替える。
Note セルは対象外。

### DocInsertNote[nb] → Null
カーソル位置に Note スタイルのセルを挿入する。
ノートブックに "Note" スタイル定義があればそれを使い、なければカスタム定義（薄黄背景、左枠線）で挿入する。

### DocExportMarkdown[nb] → String | $Failed
ノートブックを Markdown 形式でエクスポートする。
出力先: `NotebookDirectory[] / <ノートブック名>_md/`
Note セルは除外。ラスター画像 → PNG、ベクター/計算結果 → PDF。Input セル → コードブロック、数式 → TeX。

### DocExportLaTeX[nb] → String | $Failed
ノートブックを LaTeX 形式でエクスポートする。
出力先: `NotebookDirectory[] / <ノートブック名>_LaTeX/`
Note セルは除外。画像・数式処理は DocExportMarkdown と同様。

### ShowDocPalette[] → Null
ドキュメント作成用パレットを表示する。
展開・翻訳・同期・切替・削除・メモ挿入・一括表示切替・エクスポートボタンを含む。
既存パレットがあれば閉じてから再表示する。

## 変数

### $DocTranslationLanguage
型: String, 初期値: `$Language` が英語以外なら `"English"`、英語なら `"Japanese"`
翻訳先言語名。任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`

## セルモードと TaggingRules 構造

各セルの TaggingRules に以下のキーでメタデータを保持する。

| キーパス | 値例 | 意味 |
|---|---|---|
| `{"documentation", "mode"}` | `"idea"` / `"paragraph"` / `"translated"` | 現在の表示モード |
| `{"documentation", "alternate"}` | String | トグル先テキスト |
| `{"documentation", "translation"}` | String | 翻訳テキスト |
| `{"documentation", "translationSrc"}` | String | 翻訳元テキスト |
| `{"documentation", "showTranslation"}` | True/False | 翻訳表示中かどうか |

## セル視覚スタイル（内部定数）

| モード | 枠線色 |
|---|---|
| パラグラフ (`"paragraph"`) | 緑 RGBColor[0.3, 0.6, 0.5] |
| アイデア (`"idea"`) | 琥珀色 RGBColor[0.8, 0.65, 0.3] |
| 翻訳表示 (`showTranslation=True`) | 青 RGBColor[0.3, 0.45, 0.75] |
| 翻訳付き元テキスト | 水色 RGBColor[0.5, 0.75, 0.9] |

Background と CellDingbat は NBAccess の管轄であり Documentation 側では変更しない。

## 典型的な使用パターン

```mathematica
(* パレット経由が標準使用法 *)
ShowDocPalette[]

(* プログラム的に使う場合 *)
nb = EvaluationNotebook[];
DocExpandIdea[nb, 3]          (* セル3のアイデアを展開 *)
DocToggleView[nb, 3]          (* アイデア↔パラグラフ切替 *)
DocInsertNote[nb]             (* メモセル挿入 *)
DocExportMarkdown[nb]         (* Markdown エクスポート *)
DocExportLaTeX[nb]            (* LaTeX エクスポート *)

(* 翻訳先言語を変更してから使う *)
$DocTranslationLanguage = "French";
```

## 依存パッケージ

- NBAccess: https://github.com/transreal/NBAccess — セルアクセス・LLM ルーティング・プライバシー管理
- claudecode: https://github.com/transreal/claudecode — LLM コールバック・パレット設定