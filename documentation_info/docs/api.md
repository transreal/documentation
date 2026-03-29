# Documentation` API Reference

パッケージ: `Documentation`
依存: NBAccess`, ClaudeCode`
読み込み: `Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]`

アウトラインプロセッサ拡張。アイデアテキストをLLMでパラグラフに展開・翻訳・同期し、Markdown/LaTeX/Word形式でエクスポートする。

## コア関数

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストをLLMでパラグラフに展開する。元のアイデアはTaggingRulesに保存される。パラグラフ表示中の場合はプロンプト・指示・文脈に従いインプレース更新する。
→ Null（非同期実行）
Options: Fallback -> False （True でフォールバックLLMを使用）

例: `DocExpandIdea[EvaluationNotebook[], 3, Fallback -> True]`

### DocToggleView[nb, cellIdx] → Null | String
セルのアイデア↔パラグラフ↔翻訳表示を循環切替する。現在表示中の内容（編集済みでも）を保存してから切り替える。メタセル（Note/Dictionary/Directive）は対象外。

例: `DocToggleView[EvaluationNotebook[], 5]`

### DocSplitCell[nb, cellIdx] → Null
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中は表示テキストと保存データを対応位置で分割し、プロンプトがあればLLMで前半・後半用に再生成する。

### DocMergeCells[nb, cellIdxs] → Null
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し、最初のセルに統合する。モード・スタイルは最初のセルを維持する。

例: `DocMergeCells[EvaluationNotebook[], {2, 3, 4}]`

## セル挿入

### DocInsertNote[nb] → Null
現在のカーソル位置にNoteスタイルのセルを挿入する。スタイル"Note"が定義済みならそれを使い、なければカスタム定義（薄い黄色背景、左枠線）を適用する。

### DocInsertDictionary[nb] → Null
現在のカーソル位置にDictionaryスタイルのセルを挿入する。形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語1", "term1", "文脈"}, ...}`。翻訳時の用語対応指定用。

### DocInsertDirective[nb] → Null
現在のカーソル位置にDirectiveスタイルのセルを挿入する。展開・翻訳・同期の実行時にLLMが順守すべき指示を記載する。複数配置可能。

### DocInsertBibliography[nb] → Null
現在のカーソル位置にBibliographyスタイルのセルを挿入する。形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}`。本文中で `<<cite:key>>` と記述するとエクスポート時に自動変換される。

## 図・参照

### DocEditFigureMeta[nb, cellIdx] → Null | $Failed
画像セルの図メタデータ（ラベル・キャプション）を編集するダイアログを表示する。本文中で `<<fig:label>>` と記述するとエクスポート時に自動変換される。画像セル以外では$Failedを返す。

### DocEditRefSources[nb, cellIdx] → Null
セルの依存資料を編集する。アタッチされたPDFのうち、そのセルの内容生成に使われた資料と参照ページ番号を設定する。LaTeX+Mathエクスポート時に該当ページのみをLLMに送付してトークン消費を削減する。

### DocAutoInsertCitations[nb] → Null
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLMが本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliographyセルが存在しなければ末尾に自動生成する。

## エクスポート

### DocExportMarkdown[nb] → Null
ノートブックをMarkdown形式でエクスポートする。出力先: `NotebookDirectory[] / <ノートブック名>_md/`。Note/Dictionary/Directive/Bibliographyスタイルのセルは除外。画像はラスター→PNG、ベクター/計算結果→PDFで保存。`<<fig:label>>`と`<<cite:key>>`は自動変換。InputセルはMathematicaコードブロック、数式はTeXに変換される。

### DocExportLaTeX[nb, opts]
ノートブックをLaTeX形式でエクスポートする。出力先: `NotebookDirectory[] / <ノートブック名>_LaTeX/`。`<<fig:label>>`は`\ref{fig:label}`に、`<<cite:key>>`は`\cite{key}`に変換される。Note/Dictionary/Directive/Bibliographyセルは除外。
→ Null
Options: "MathFormat" -> False （True でLLMによる数式自動フォーマット）

例: `DocExportLaTeX[EvaluationNotebook[], "MathFormat" -> True]`

### DocExportWord[nb, opts]
ノートブックをWord(.docx)形式でエクスポートする。内部でDocExportMarkdownを実行しPandocで変換する。出力先: `NotebookDirectory[] / <ノートブック名>_md/<ノートブック名>.docx`。Pandocのインストールが必要。
→ Null
Options: "ReferenceDoc" -> None （テンプレート.docxファイルのパス）

例: `DocExportWord[EvaluationNotebook[], "ReferenceDoc" -> "/path/to/template.docx"]`

## パレット

### ShowDocPalette[] → Null
ドキュメント作成用パレットを表示する。展開・トグル・翻訳・同期・エクスポート等のボタンを含む。

## 変数

### $DocTranslationLanguage
型: String, 初期値: `$Language`が英語以外なら`"English"`、英語なら`"Japanese"`
翻訳先の言語名。ユーザーが任意の言語名に変更可能。

例: `$DocTranslationLanguage = "French"`

## セルモードとTaggingRules構造

セルのTaggingRulesに以下のキーで状態を保存する:

- `{"documentation", "mode"}` — `"idea"` | `"paragraph"` | `"translated"` | 未設定
- `{"documentation", "alternate"}` — 非表示側のテキスト（アイデア表示中はパラグラフ、逆も然り）
- `{"documentation", "translation"}` — 翻訳テキスト
- `{"documentation", "translationSrc"}` — 翻訳元テキスト（翻訳表示時に保存）
- `{"documentation", "showTranslation"}` — True のとき翻訳を表示中
- `{"documentation", "excludeExport"}` — True のときエクスポートから除外
- `{"documentation", "figLabel"}` — 図の参照ラベル
- `{"documentation", "figCaption"}` — 図のキャプション
- `{"documentation", "refSources"}` — 依存資料リスト（PDFパスと参照ページ）

## セルスタイルとエクスポート除外

以下のスタイルのセルはエクスポート（Markdown/LaTeX/Word）から**常に除外**される:
- `"Note"` — メモ・注釈
- `"Dictionary"` — 用語辞書
- `"Directive"` — LLM指示
- `"Bibliography"` — 参考文献リスト（ただし `<<cite:key>>` 解決には使用される）

`DocEditFigureMeta` または `iDocToggleExportExclude` でセル単位の除外フラグ（`excludeExport`）を設定することもできる。

## 参照マーカー構文

本文テキスト中に以下のマーカーを埋め込むとエクスポート時に自動変換される:

- `<<fig:label>>` — Markdown: `![...](path){#fig-label}` / LaTeX: `\ref{fig:label}`
- `<<cite:key>>` — Markdown: `[key]` / LaTeX: `\cite{key}`