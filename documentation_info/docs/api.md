# Documentation` API Reference

パッケージ: `Documentation`
リポジトリ: https://github.com/transreal/documentation
依存: [NBAccess`](https://github.com/transreal/NBAccess), [ClaudeCode`](https://github.com/transreal/claudecode)
ロード方法: `Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]`

## 概要

アウトラインプロセッサ拡張パッケージ。アイデア → パラグラフ展開、翻訳、エクスポートを LLM 経由で提供する。セル内容へのアクセスはすべて NBAccess` 経由、LLM 呼び出しは `NBAccess`NBCellTransformWithLLM` 経由で行う。

## セルモード

各セルは TaggingRules にモードを持つ。

| モード | 説明 | 枠線色 |
|--------|------|--------|
| `"idea"` | プロンプト（アイデア）表示中 | 琥珀色 |
| `"paragraph"` | 展開済みパラグラフ表示中 | 緑 |
| `"translated"` | 翻訳付きセル（元テキスト表示） | 水色 |
| 翻訳表示中 | showTranslation=True 時 | 青 |
| `"compute"` | 計算コード表示中 | （内部） |
| `"computePrompt"` | 計算プロンプト表示中 | 琥珀色 |

## 展開・トグル

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストを LLM でパラグラフに展開する。パラグラフ表示中の場合はインプレース更新。元アイデアは TaggingRules に保存される。
→ Null（非同期実行）
Options: `Fallback -> False`（True で代替 LLM を使用）
例: `DocExpandIdea[EvaluationNotebook[], 3, Fallback -> True]`

### DocToggleView[nb, cellIdx]
セルのアイデア ↔ パラグラフ ↔ 翻訳の表示を循環切替する。編集内容を保存してから切り替え、編集があれば非同期で他レイヤーを LLM 同期する。
→ String（切替後の表示テキスト）または Null

### DocSplitCell[nb, cellIdx]
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中は表示テキストと保存データを対応位置で分割し、プロンプトがあれば LLM で再生成する。
→ Null

### DocMergeCells[nb, cellIdxs]
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し、最初のセルに統合する。モード・スタイルは最初のセルを維持。
→ Null

## 翻訳・同期

### DocTranslate[nb, cellIdx, opts]
指定セルを翻訳する。パラグラフモードまたは通常セルが対象。翻訳結果は TaggingRules に保持し、DocToggleView で切替可能。
→ Null（非同期実行）
Options: `Fallback -> False`

### DocSync[nb, cellIdx, opts]
セルのレイヤー（パラグラフ・翻訳・アイデア）を LLM で再同期する。
→ Null（非同期実行）
Options: `Fallback -> False`

### DocCompute[nb, cellIdx, opts]
計算モードセルの処理を実行する。
→ Null（非同期実行）
Options: `Fallback -> False`

### $DocTranslationLanguage
型: String, 初期値: `$Language` が英語以外なら `"English"`、英語なら `"Japanese"`
翻訳先の言語名。任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`

## セル挿入

### DocInsertNote[nb]
現在のカーソル位置に Note スタイルのセルを挿入する。スタイル定義が存在すればそれを使用し、なければカスタム定義（薄い黄色背景、左側琥珀色枠線）で挿入する。
→ Null

### DocInsertDictionary[nb]
現在のカーソル位置に Dictionary スタイルのセルを挿入する。翻訳時の用語対応を指定するセル。形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語", "term", "文脈"}, ...}`。1行目はヘッダー（`<<>>` で囲む）。
→ Null

### DocInsertDirective[nb]
現在のカーソル位置に Directive スタイルのセルを挿入する。展開・翻訳・同期時に LLM が順守すべき指示を記載する。複数配置可能。
→ Null

### DocInsertBibliography[nb]
現在のカーソル位置に Bibliography スタイルのセルを挿入する。形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}`。本文中で `<<cite:key>>` と記述するとエクスポート時に自動変換される。
→ Null

## メタデータ編集

### DocEditFigureMeta[nb, cellIdx]
画像セルのラベル（参照用キー）とキャプションを設定するダイアログを表示する。本文中で `<<fig:label>>` と記述するとエクスポート時に自動変換される。画像セル以外では `$Failed` を返す。
→ Null または $Failed

### DocEditRefSources[nb, cellIdx]
セルの依存資料（アタッチ PDF）と参照ページ番号を編集する。LaTeX+Math エクスポート時に該当ページのみを LLM に送付してトークン消費を削減する。
→ Null

## 自動引用

### DocAutoInsertCitations[nb]
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLM が本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliography セルが存在しなければ末尾に自動生成する。
→ Null（非同期実行）

## エクスポート

### DocExportMarkdown[nb, opts]
ノートブックを Markdown 形式でエクスポートする。
出力先: `NotebookDirectory[]/ノートブック名_md/`
Note, Dictionary, Directive, Bibliography スタイルのセルは除外。画像はラスター→PNG、ベクター/計算結果→PDF で保存。`<<fig:label>>` と `<<cite:key>>` は自動変換。Input セルはコードブロック、数式は TeX に変換。
→ String（出力ディレクトリパス）または $Failed
Options: `"MathFormat" -> False`（True で LLM による数式自動フォーマット）

### DocExportLaTeX[nb, opts]
ノートブックを LaTeX 形式でエクスポートする。
出力先: `NotebookDirectory[]/ノートブック名_LaTeX/`
Note, Dictionary, Directive, Bibliography スタイルのセルは除外。`<<fig:label>>` は `\ref{fig:label}` に、`<<cite:key>>` は `\cite{key}` に変換。
→ String（出力ディレクトリパス）または $Failed
Options: `"MathFormat" -> False`（True で LLM による数式自動フォーマット）

### DocExportWord[nb, opts]
ノートブックを Word (.docx) 形式でエクスポートする。内部で DocExportMarkdown を実行し Pandoc で変換。Pandoc のインストールが必要。
出力先: `NotebookDirectory[]/ノートブック名_md/ノートブック名.docx`
→ String（.docx ファイルパス）または $Failed
Options: `"ReferenceDoc" -> None`（テンプレート .docx のパス）, `"MathFormat" -> False`
例: `DocExportWord[EvaluationNotebook[], "ReferenceDoc" -> "/path/template.docx"]`

## パレット

### ShowDocPalette[]
ドキュメント作成用パレットを表示する。展開・トグル・翻訳・エクスポート等の操作ボタンを含む。
→ NotebookObject

## 参照マーカー構文

エクスポート時に自動変換されるインラインマーカー。

| マーカー | 変換先 (Markdown) | 変換先 (LaTeX) |
|---------|------------------|----------------|
| `<<fig:label>>` | 図番号テキスト | `\ref{fig:label}` |
| `<<cite:key>>` | 著者 (年) 形式 | `\cite{key}` |