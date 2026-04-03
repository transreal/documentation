# Documentation` パッケージ API リファレンス

アウトラインプロセッサ拡張パッケージ。アイデア→パラグラフ展開、翻訳、エクスポート機能を提供する。
依存: NBAccess`, ClaudeCode`

## セル操作

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストをLLMで文章品質のパラグラフに展開する。パラグラフ表示中の場合はインプレース更新。元のアイデアはTaggingRulesに保存される。
→ $Failed | Null
Options: Fallback -> False (Trueでフォールバックモデルを使用)
例: DocExpandIdea[EvaluationNotebook[], 3, Fallback -> True]

### DocToggleView[nb, cellIdx] → Null | String
セルのアイデア↔パラグラフ↔翻訳の表示を切り替える。現在の表示内容（編集済みでも）を保存してから切り替える。編集済みの場合はバックグラウンドで同期処理を実行する。

### DocSplitCell[nb, cellIdx] → Null
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中は表示テキストと保存データを対応位置で分割し、プロンプトがあればLLMで前半・後半用に再生成する。

### DocMergeCells[nb, cellIdxs] → Null
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し最初のセルに統合する。モード・スタイルは最初のセルを維持する。
例: DocMergeCells[EvaluationNotebook[], {2, 3, 4}]

## セル挿入

### DocInsertNote[nb] → Null
現在のカーソル位置にNoteスタイルのセルを挿入する。ノートブックにスタイル"Note"が定義済みならそれを使い、なければカスタム定義（薄い黄色背景、左琥珀色枠線）のセルを挿入する。

### DocInsertDictionary[nb] → Null
現在のカーソル位置にDictionaryスタイルのセルを挿入する。翻訳時の用語対応指定用。形式: {{<<Japanese>>, <<English>>, <<Context>>}, {"用語1", "term1", "文脈"}, ...}

### DocInsertDirective[nb] → Null
現在のカーソル位置にDirectiveスタイルのセルを挿入する。展開・翻訳・同期実行時にLLMが順守すべき指示を記載する。複数配置可能。

### DocInsertBibliography[nb] → Null
現在のカーソル位置にBibliographyスタイルのセルを挿入する。形式: {{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}。本文中で`<<cite:key>>`と記述するとエクスポート時に自動変換される。

## メタデータ編集

### DocEditFigureMeta[nb, cellIdx] → Null | $Failed
画像セルの図メタデータ（ラベル・キャプション）を編集するダイアログを表示する。本文中で`<<fig:label>>`と記述するとエクスポート時に自動変換される。画像セルでない場合は$Failedを返す。

### DocEditRefSources[nb, cellIdx] → Null
セルの依存資料を編集するダイアログを表示する。アタッチされたPDFのうち、そのセルの内容生成に使われた資料と参照ページ番号を設定する。LaTeX+Mathエクスポート時に該当ページのみをLLMに送付してトークン消費を削減する。

### DocAutoInsertCitations[nb] → Null
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLMが本文中の適切な位置に`<<cite:key>>`マーカーを挿入する。Bibliographyセルが存在しなければ末尾に自動生成する。

## エクスポート

### DocExportMarkdown[nb, opts]
ノートブックをMarkdown形式でエクスポートする。出力先: NotebookDirectory[]/<ノートブック名>_md/。Note/Dictionary/Directive/Bibliographyスタイルのセルは除外。画像はラスター→PNG、ベクター/計算結果→PDF。`<<fig:label>>`と`<<cite:key>>`は自動変換される。InputセルはMathematicaコードブロック、数式はTeXに変換される。
→ Null
Options: "MathFormat" -> False (TrueでLLMによる数式自動フォーマット)

### DocExportLaTeX[nb, opts]
ノートブックをLaTeX形式でエクスポートする。出力先: NotebookDirectory[]/<ノートブック名>_LaTeX/。Note/Dictionary/Directive/Bibliographyスタイルのセルは除外。`<<fig:label>>`は`\ref{fig:label}`に、`<<cite:key>>`は`\cite{key}`に変換される。
→ Null
Options: "MathFormat" -> False (TrueでLLMによる数式自動フォーマット)

### DocExportWord[nb, opts]
ノートブックをWord (.docx)形式でエクスポートする。内部でDocExportMarkdownを実行後、Pandocで.docxに変換する。Pandocのインストールが必要。出力先: NotebookDirectory[]/<ノートブック名>_md/<ノートブック名>.docx
→ Null
Options: "ReferenceDoc" -> None (テンプレート.docxファイルのパス), "MathFormat" -> False

## 翻訳・同期（オプション宣言のみ）

### DocTranslate[..., opts]
Options: Fallback -> False

### DocSync[..., opts]
Options: Fallback -> False

### DocCompute[..., opts]
Options: Fallback -> False

## パレット

### ShowDocPalette[] → Null
ドキュメント作成用パレットを表示する。展開・トグル・翻訳・エクスポート等のボタンを含む。

## 変数

### $DocTranslationLanguage
型: String
翻訳先の言語名。初期値: $Languageが英語以外なら"English"、英語なら"Japanese"。ユーザーが任意の言語名に変更可能。
例: $DocTranslationLanguage = "French"

## セルモードとTaggingRules

各セルはTaggingRulesにメタデータを保持する。キーパス基底は"documentation"。

| TaggingRulesパス | 内容 |
|---|---|
| {"documentation", "mode"} | "idea" / "paragraph" / "translated" / "compute" / "computePrompt" |
| {"documentation", "alternate"} | トグル相手のテキスト（パラグラフ↔アイデア） |
| {"documentation", "translation"} | 翻訳済みテキスト |
| {"documentation", "translationSrc"} | 翻訳元テキスト |
| {"documentation", "showTranslation"} | True/False（翻訳表示中フラグ） |
| {"documentation", "excludeExport"} | True（エクスポート除外フラグ） |
| {"documentation", "figLabel"} | 図の参照ラベル文字列 |
| {"documentation", "figCaption"} | 図のキャプション文字列 |
| {"documentation", "cleanText"} | 編集前クリーンコピー（編集検出用） |
| {"documentation", "refSources"} | 依存資料リスト |

## セルスタイルとビジュアル

| モード | 枠線色 |
|---|---|
| paragraph（パラグラフ） | 緑 RGBColor[0.3, 0.6, 0.5] |
| idea（アイデア） | 琥珀色 RGBColor[0.8, 0.65, 0.3] |
| translated（翻訳表示中） | 青 RGBColor[0.3, 0.45, 0.75] |
| translated元テキスト表示 | 水色 RGBColor[0.5, 0.75, 0.9] |

メタセル（Note/Dictionary/Directive/Bibliography）はエクスポート・展開の対象外。