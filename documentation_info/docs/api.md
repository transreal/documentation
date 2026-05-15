# documentation API リファレンス

Wolfram Language パッケージ `Documentation`。アウトラインプロセッサ拡張: アイデア → パラグラフ展開システム。依存: [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode)。

## アイデア展開・トグル

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストを LLM で文章品質のパラグラフに展開する。元のアイデアはセルの TaggingRules に保存される。既にパラグラフ表示中の場合は、プロンプト・指示・文脈に従い現在のパラグラフ文章を尊重しつつインプレース更新する。Note/Dictionary/Directive セルは対象外。
→ String | $Failed
Options: Fallback -> False (LLM フォールバックを使うか)
例: `DocExpandIdea[EvaluationNotebook[], 3]`

### DocToggleView[nb, cellIdx] → String | Null | $Failed
セルのアイデアとパラグラフの表示を切り替える。現在表示中の内容（編集済みでも）を保存してから切り替え、編集があった場合はバックグラウンドで他レイヤー（パラグラフ/翻訳/アイデア）を LLM で再生成する。翻訳付きセル・計算モード・通常 idea↔paragraph の3経路に対応。

## テキスト品質改善

### DocRefine[nb, cellIdx, opts]
選択セルのテキストを LLM で校正する。文法的・表現上の不自然さを最小限の修正で訂正し、元の意味・構成・文体・トーンを完全に保持する。Directive/Dictionary セルの指示は厳守。翻訳付きセルの場合は翻訳も連鎖更新する。対象外: idea モード、compute モード、メタセル。
→ String | $Failed
Options: Fallback -> False
例: `DocRefine[EvaluationNotebook[], 3]`

### DocPolish[nb, cellIdx, opts]
選択セルのテキストを LLM でより完璧に書き直す。内容（情報・主旨・意図）は保持しつつ、文の構成や言い回しを必要に応じて大きく変更する。Directive/Dictionary セルの指示は厳守。翻訳付きセルの場合は翻訳も連鎖更新する。対象外: idea モード、compute モード、メタセル。
→ String | $Failed
Options: Fallback -> False
例: `DocPolish[EvaluationNotebook[], 3]`

## セル操作

### DocSplitCell[nb, cellIdx] → Null | $Failed
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中はテキストと保存データを対応位置で分割し、プロンプトがあれば LLM で前半・後半用に再生成する。普通のセルはテキストを単純分割する。

### DocMergeCells[nb, cellIdxs] → Null | $Failed
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し、最初のセルに統合する。モード・スタイルは最初のセルを維持する。

## 一括処理

### DocSyncAll[nb, opts]
ノートブック内の全 paragraph/idea セルを、現在の指示(Directive)・辞書(Dictionary)・プロンプトに従って一括再生成する。翻訳があれば連鎖的に翻訳も更新する。指示/辞書セルの最終更新時刻より後に編集された対象セルはスキップする。確認ダイアログで実行前に警告。処理は非同期。
→ Null | $Failed
Options: Fallback -> False

## メタセル挿入

### DocInsertNote[nb] → Null
現在のカーソル位置に Note スタイルのセルを挿入する。既にスタイル `"Note"` が定義されていればそれを使い、なければカスタム定義の Note セル（薄い黄色背景）を挿入する。

### DocInsertDictionary[nb] → Null
現在のカーソル位置に Dictionary スタイルのセルを挿入する。翻訳時の用語対応辞書。形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語1", "term1", "文脈"}, ...}`。1行目はヘッダー（`<<>>` で囲む）、2行目以降が Context における用語対応。

### DocInsertDirective[nb] → Null
現在のカーソル位置に Directive スタイルのセルを挿入する。展開・翻訳・同期時に LLM が順守すべき指示を記載する。複数の Directive セルを配置可能。

### DocInsertBibliography[nb] → Null
現在のカーソル位置に Bibliography スタイルのセルを挿入する。参考文献リスト管理用。形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}`。本文中の `<<cite:key>>` がエクスポート時に自動変換される。

## 図・参照管理

### DocEditFigureMeta[nb, cellIdx] → Null
画像セルの図メタデータを編集する。ラベル（参照用キー）とキャプションを設定するダイアログを表示。本文中の `<<fig:label>>` がエクスポート時に自動変換される。

### DocEditRefSources[nb, cellIdx] → Null
セルの依存資料を編集する。アタッチされた PDF のうち、そのセルの内容生成に使われた資料と参照ページ番号を設定する。LaTeX+Math エクスポート時に該当ページのみを LLM に送付してトークン消費を削減する。

### DocAutoInsertCitations[nb] → Null
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLM が本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliography セルが存在しなければ末尾に自動生成する。

## エクスポート

### DocExportMarkdown[nb, opts]
ノートブックを Markdown 形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_md/`。Note/Dictionary/Directive/Bibliography スタイルのセルは出力から除外される。画像はラスター→PNG、ベクター/計算結果→PDF で保存。`<<fig:label>>` と `<<cite:key>>` は自動変換、Input セルはコードブロック、数式は TeX に変換される。
→ String (出力ディレクトリ) | $Failed
Options: "MathFormat" -> False (True で LLM による数式自動フォーマット)

### DocExportLaTeX[nb, opts]
ノートブックを LaTeX 形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_LaTeX/`。Note/Dictionary/Directive/Bibliography スタイルのセルは出力から除外される。画像はラスター→PNG、ベクター/計算結果→PDF で保存。`<<fig:label>>` は `\ref{fig:label}` に、`<<cite:key>>` は `\cite{key}` に変換される。
→ String (出力ディレクトリ) | $Failed
Options: "MathFormat" -> False (True で LLM による数式自動フォーマット)

### DocExportWord[nb, opts]
ノートブックを Word (.docx) 形式でエクスポートする。内部で DocExportMarkdown を実行し、Pandoc で .docx に変換する。出力先: `NotebookDirectory[]/<ノートブック名>_md/<ノートブック名>.docx`。Pandoc がインストールされている必要がある。
→ String (出力ファイル) | $Failed
Options: "ReferenceDoc" -> None (テンプレート .docx ファイルのパス), "MathFormat" -> False

## パレット

### ShowDocPalette[] → NotebookObject
ドキュメント作成用パレットを表示する。アイデア展開・トグル・翻訳・同期・メタセル挿入・エクスポート等の全機能をボタンから呼び出せる。

## グローバル変数

### $DocTranslationLanguage
型: String, 初期値: `If[$Language === "English", "Japanese", "English"]`
翻訳先の言語名。ユーザーが任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`

## 内部宣言（Options のみ参照用）

以下の関数は `Options[...]` 宣言が公開シンボル空間に存在するが、本リファレンス記載の公開API経由でアクセスする想定:
- `DocTranslate` — Options: Fallback -> False
- `DocSync` — Options: Fallback -> False
- `DocCompute` — Options: Fallback -> False

## 共通オプション意味論

- `Fallback -> True | False`: LLM 呼び出しで `ClaudeCode\`GetPaletteFallback[]` 相当のフォールバックモデルを使うかどうか。パレット経由の呼び出しではパレットの設定値が自動的に渡される。
- `"MathFormat" -> True | False`: エクスポート時に数式表現を LLM で自動整形するか。`True` にすると追加の LLM 呼び出しが発生する。
- `"ReferenceDoc" -> None | _String`: Word エクスポート時の Pandoc 参照テンプレート .docx へのパス。

## モード一覧（TaggingRules 上の `mode` 値）

- `"idea"`: アイデア（プロンプト）表示中。琥珀色の左枠。
- `"paragraph"`: 展開済みパラグラフ表示中。緑の左枠。
- `"translated"`: 翻訳付きセル。元テキスト表示時は水色枠、翻訳表示時は青枠。
- `"compute"`: 計算コード表示中。
- `"computePrompt"`: 計算プロンプト表示中。

## 表示状態切替の挙動

`DocToggleView` の遷移ルール:
- `paragraph` (翻訳あり) → 翻訳表示（青枠）→ `idea`（琥珀枠）→ `paragraph`（緑枠）
- `paragraph` (翻訳なし) → `idea` ↔ `paragraph`
- `translated`: 元テキスト（水色枠）↔ 翻訳（青枠）
- `compute` ↔ `computePrompt`: コード ↔ プロンプト
編集中に切り替えた場合、編集内容は保存され、他レイヤーは非同期 LLM で再生成される。