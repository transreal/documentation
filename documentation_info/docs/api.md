# Documentation` API Reference

パッケージ: `Documentation`` — アウトラインプロセッサ拡張。アイデア→パラグラフ展開・翻訳・エクスポートを提供する。
依存: [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode)
ロード: `Needs["Documentation`"]`

## セル操作

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストをLLMでパラグラフに展開する。パラグラフ表示中は現在の文章を尊重しつつインプレース更新する。元のアイデアはTaggingRulesに保存される。Note/Dictionary/Directive/Bibliographyセルは対象外。
→ $Failed | Null
Options: Fallback -> False (TrueでフォールバックLLMを使用)

### DocToggleView[nb, cellIdx] → String | Null
セルのアイデア↔パラグラフ↔翻訳の表示を循環切替する。編集済み内容を保存してから切り替える。翻訳がある場合はパラグラフ→翻訳→アイデアの順に遷移する。

### DocSplitCell[nb, cellIdx] → Null
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中は保存データも対応位置で分割し、プロンプトがあればLLMで再生成する。普通のセルはテキストを単純に分割する。

### DocMergeCells[nb, cellIdxs] → Null
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し、モード・スタイルは最初のセルを維持する。

## セル挿入

### DocInsertNote[nb] → Null
カーソル位置にNoteスタイルのセルを挿入する。スタイル"Note"が定義済みならそれを使い、なければカスタム定義（薄い黄色背景・左枠線付き）のセルを挿入する。

### DocInsertDictionary[nb] → Null
カーソル位置にDictionaryスタイルのセルを挿入する。翻訳時にLLMが遵守する用語対応を指定する。形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語1", "term1", "文脈"}, ...}`

### DocInsertDirective[nb] → Null
カーソル位置にDirectiveスタイルのセルを挿入する。展開・翻訳・同期の実行時にLLMが順守すべき指示を記載する。複数のDirectiveセルを配置可能。

### DocInsertBibliography[nb] → Null
カーソル位置にBibliographyスタイルのセルを挿入する。形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}` 本文中の `<<cite:key>>` はエクスポート時に自動変換される。

## メタデータ編集

### DocEditFigureMeta[nb, cellIdx] → Null
画像セルのラベル（参照用キー）とキャプションを設定するダイアログを表示する。本文中の `<<fig:label>>` はエクスポート時に自動変換される。セルが画像でなければ$Failedを返す。

### DocEditRefSources[nb, cellIdx] → Null
セルの依存資料（アタッチPDFのうち内容生成に使った資料と参照ページ番号）を編集する。LaTeX+MathエクスポートでLLMへのトークン消費を削減するために使用される。

## 翻訳・同期

### DocTranslate[nb, cellIdx, opts]
セルを翻訳する。パラグラフモードと普通のセル（モード未設定）が対象。アイデアモードと翻訳表示中は不可。翻訳結果はTaggingRulesに保持し切替可能。再翻訳時は既存翻訳を踏襲して更新する。
→ Null
Options: Fallback -> False (TrueでフォールバックLLMを使用)

### DocSync[nb, cellIdx, opts]
セルのアイデアとパラグラフを同期する。
→ Null
Options: Fallback -> False (TrueでフォールバックLLMを使用)

## 引用・参照

### DocAutoInsertCitations[nb] → Null
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLMが本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliographyセルが存在しなければ末尾に自動生成する。

## 計算

### DocCompute[nb, cellIdx, opts]
セルの計算プロンプトからコードを生成・更新する。
→ Null
Options: Fallback -> False (TrueでフォールバックLLMを使用)

## エクスポート

### DocExportMarkdown[nb, opts]
ノートブックをMarkdown形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_md/`。Note/Dictionary/Directive/Bibliographyセルは除外。画像はラスター→PNG、ベクター/計算結果→PDF。`<<fig:label>>`・`<<cite:key>>`を自動変換する。InputセルはMathematicaコードブロック、数式はTeXに変換する。
→ String (出力ディレクトリパス) | $Failed
Options: "MathFormat" -> False (TrueでLLMによる数式自動フォーマット)

### DocExportLaTeX[nb, opts]
ノートブックをLaTeX形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_LaTeX/`。`<<fig:label>>`→`\ref{fig:label}`、`<<cite:key>>`→`\cite{key}`に変換する。Note/Dictionary/Directive/Bibliographyセルは除外。
→ String | $Failed
Options: "MathFormat" -> False (TrueでLLMによる数式自動フォーマット)

### DocExportWord[nb, opts]
ノートブックをWord(.docx)形式でエクスポートする。内部でDocExportMarkdownを実行後Pandocで.docxに変換する。Pandocのインストールが必要。出力先: `NotebookDirectory[]/<ノートブック名>_md/<ノートブック名>.docx`
→ String | $Failed
Options: "ReferenceDoc" -> None (テンプレート.docxファイルのパス), "MathFormat" -> False (TrueでLLM数式フォーマット)
例: `DocExportWord[EvaluationNotebook[], "ReferenceDoc" -> "/path/to/template.docx"]`

## パレット

### ShowDocPalette[] → Null
ドキュメント作成用パレットを表示する。

## 変数

### $DocTranslationLanguage
型: String, 初期値: $Languageが英語以外なら"English"、英語なら"Japanese"
翻訳先言語名。ユーザーが任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`