# Documentation` — LLM向けAPIリファレンス

パッケージ: `Documentation``
リポジトリ: https://github.com/transreal/documentation
依存: [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode)
ロード: `Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]`

アウトラインプロセッサ拡張。アイデア（プロンプト）→ LLM によるパラグラフ展開、翻訳、エクスポートを提供する。セルアクセスはすべて `NBAccess`` 経由。LLM 呼び出しは `NBAccess`NBCellTransformWithLLM` 経由。

## セル状態モデル

各セルはTaggingRulesに状態を持つ。

モード値（`"documentation"/"mode"`）:
- `"idea"` — プロンプト/アイデア表示中（琥珀色枠）
- `"paragraph"` — 展開パラグラフ表示中（緑枠）
- `"translated"` — 翻訳付きセル・元テキスト表示中（水色枠）
- `"compute"` — 計算コード表示中
- `"computePrompt"` — 計算プロンプト表示中

翻訳表示中は `"documentation"/"showTranslation"` が `True`（青枠）。

TaggingRulesキー（参照用）:
- `{"documentation","alternate"}` — 非表示側のテキスト
- `{"documentation","translation"}` — 翻訳テキスト
- `{"documentation","translationSrc"}` — 翻訳元パラグラフ
- `{"documentation","showTranslation"}` — 翻訳表示フラグ
- `{"documentation","excludeExport"}` — エクスポート除外フラグ
- `{"documentation","figLabel"}` — 図ラベル
- `{"documentation","figCaption"}` — 図キャプション
- `{"documentation","refSources"}` — 依存資料リスト

メタセル（Note/Dictionary/Directive/Bibliography スタイル）は展開・翻訳・エクスポートの対象外。

## コア関数

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストをLLMでパラグラフに展開する。パラグラフ表示中なら現在のパラグラフを尊重しつつインプレース更新する。元アイデアはTaggingRulesに保存される。
→ Null（非同期）
Options: `Fallback -> False`（True でフォールバックLLM使用）

### DocToggleView[nb, cellIdx]
セルのアイデア⇄パラグラフ⇄翻訳の表示を循環的に切り替える。編集済みコンテンツを保存してから切り替え、必要に応じてバックグラウンドで他レイヤーを同期する。
→ 切替後の表示テキスト（String）または Null

### DocSplitCell[nb, cellIdx]
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中はLLMで前後を再生成する。
→ Null

### DocMergeCells[nb, cellIdxs]
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し、最初のセルのモード・スタイルを維持する。
→ Null

例:
```
DocMergeCells[EvaluationNotebook[], {3, 4, 5}]
```

### DocSyncAll[nb, opts]
ノートブック内の全 paragraph/idea セルを現在のDirective・Dictionary・プロンプトに従って一括再生成する。指示/辞書セルの最終更新時刻より後に編集されたセルはスキップ。確認ダイアログ表示後、非同期で処理する。
→ Null
Options: `Fallback -> False`

### DocTranslate[opts]
翻訳関数。Options: `Fallback -> False`

### DocSync[opts]
単一セル同期関数。Options: `Fallback -> False`

### DocCompute[opts]
計算セル処理関数。Options: `Fallback -> False`

## 挿入関数

### DocInsertNote[nb]
カーソル位置にNoteスタイルセルを挿入する。ノートブックに"Note"スタイルが定義済みならそれを使い、なければカスタム定義（薄黄背景・琥珀色枠）で挿入する。
→ Null

### DocInsertDictionary[nb]
カーソル位置にDictionaryスタイルセルを挿入する。翻訳時の用語対応を指定するテーブル形式。形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語", "term", "文脈"}, ...}`（1行目はヘッダー）。
→ Null

### DocInsertDirective[nb]
カーソル位置にDirectiveスタイルセルを挿入する。展開・翻訳・同期実行時にLLMが順守する指示を記載する。複数配置可能。
→ Null

### DocInsertBibliography[nb]
カーソル位置にBibliographyスタイルセルを挿入する。形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}`。本文中で `<<cite:key>>` と記述するとエクスポート時に自動変換される。
→ Null

### DocEditFigureMeta[nb, cellIdx]
画像セルの図ラベルとキャプションを設定するダイアログを表示する。本文中で `<<fig:label>>` と記述するとエクスポート時に自動変換される。画像セル以外では `$Failed` を返す。
→ Null または $Failed

### DocEditRefSources[nb, cellIdx]
セルの依存資料（アタッチされたPDFのうち内容生成に使われたもの）と参照ページ番号を設定するダイアログを表示する。LaTeX+Mathエクスポート時に該当ページのみLLMに送付してトークン消費を削減する。
→ Null

## 引用・自動処理

### DocAutoInsertCitations[nb]
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLMが本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliographyセルが存在しなければ末尾に自動生成する。
→ Null（非同期）

## エクスポート関数

### DocExportMarkdown[nb, opts]
ノートブックをMarkdown形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_md/`。Note/Dictionary/Directive/BibliographyセルはID除外。画像はラスター→PNG、ベクター→PDF。`<<fig:label>>`・`<<cite:key>>` は自動変換される。Inputセルはコードブロック、数式はTeXに変換される。
→ Null
Options: `"MathFormat" -> False`（True でLLMによる数式自動フォーマット）

### DocExportLaTeX[nb, opts]
ノートブックをLaTeX形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_LaTeX/`。`<<fig:label>>` → `\ref{fig:label}`、`<<cite:key>>` → `\cite{key}` に変換。
→ Null
Options: `"MathFormat" -> False`

### DocExportWord[nb, opts]
ノートブックをWord（.docx）形式でエクスポートする。内部でDocExportMarkdownを実行し、Pandocで.docxに変換する。Pandocのインストールが必要。出力先: `NotebookDirectory[]/<ノートブック名>_md/<ノートブック名>.docx`
→ Null
Options: `"ReferenceDoc" -> None`（テンプレート.docxファイルのパス）, `"MathFormat" -> False`

例:
```
DocExportWord[EvaluationNotebook[], "ReferenceDoc" -> "/path/to/template.docx"]
```

## パレット

### ShowDocPalette[]
ドキュメント作成用パレットを表示する。展開・トグル・翻訳・同期・挿入・エクスポートのボタンを提供する。
→ Null

## グローバル変数

### $DocTranslationLanguage
型: String, 初期値: `$Language` が "English" 以外なら `"English"`、"English" なら `"Japanese"`
翻訳先言語名。ユーザーが任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`