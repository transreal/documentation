# documentation パッケージ API リファレンス

パッケージコンテキスト: `Documentation``
ロード方法: `Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]`
依存: [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode)
用途: Mathematica ノートブックでのドキュメント執筆支援。アイデア→パラグラフ展開、翻訳、エクスポートを提供する。

## セルモード概念

各セルは `TaggingRules[{"documentation","mode"}]` にモード文字列を持つ。

| モード値 | 表示内容 | 枠線色 |
|---|---|---|
| `"idea"` | プロンプト/アイデアテキスト | 琥珀色 |
| `"paragraph"` | 展開済みパラグラフ | 緑 |
| `"translated"` | 翻訳付きセル（元テキスト表示中） | 水色 |
| `"compute"` | 計算コード | — |
| `"computePrompt"` | 計算プロンプト | 琥珀色 |
| `"figClean"` | 清書済み図 | — |
| `"figOutline"` | 手書き図 | — |

翻訳表示中は `TaggingRules[{"documentation","showTranslation"}] === True`（青枠）。モード未設定は通常セル。

## TaggingRules パス一覧

| パス | 用途 |
|---|---|
| `{"documentation","alternate"}` | 非表示側のテキスト（idea⇄paragraph の交替値） |
| `{"documentation","mode"}` | セルモード文字列 |
| `{"documentation","translation"}` | 翻訳テキスト |
| `{"documentation","translationSrc"}` | 翻訳元テキスト |
| `{"documentation","showTranslation"}` | 翻訳表示フラグ（True/False） |
| `{"documentation","excludeExport"}` | エクスポート除外フラグ（True） |
| `{"documentation","figLabel"}` | 図の参照キー |
| `{"documentation","figCaption"}` | 図のキャプション |
| `{"documentation","cleanText"}` | 編集追跡用クリーンテキスト |
| `{"documentation","cleanMode"}` | 編集追跡用モード文字列 |
| `{"documentation","refSources"}` | 依存資料リスト（PDF パス・ページ番号） |
| `{"documentation","figOutline"}` | 元の手書き図データ（Compress 文字列） |
| `{"documentation","figCleanBoxes"}` | 清書後の Graphics ボックス（Compress 文字列） |
| `{"documentation","figCleanCode"}` | 清書時 LLM 生成 Graphics コード |

## パブリック関数

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストを LLM でパラグラフに展開する。パラグラフ表示中の場合はインプレース更新。元のアイデアは `alternate` タグに保存される。
→ Null（副作用）
Options: `Fallback -> False` （Trueでフォールバック LLM を使用）
例: `DocExpandIdea[EvaluationNotebook[], 3]`

### DocToggleView[nb, cellIdx]
セルのアイデア↔パラグラフ↔翻訳の表示を循環切替する。編集済み内容を保存してから切替え、編集があれば非同期で他レイヤーを同期する。
→ Null（副作用）
例: `DocToggleView[EvaluationNotebook[], 5]`

### DocTranslate[nb, cellIdx, opts]
指定セルを翻訳する。`$DocTranslationLanguage` の言語に翻訳し、結果を `translation` タグに保存。`translated` モードに設定する。
→ Null（副作用）
Options: `Fallback -> False`

### DocSync[nb, cellIdx, opts]
指定セルを現在の Directive/Dictionary に従って再同期する。
→ Null（副作用）
Options: `Fallback -> False`

### DocSyncAll[nb, opts]
ノートブック内の全 paragraph/idea セルを Directive・Dictionary・プロンプトに従って一括再生成する。Directive/Dictionary の最終更新時刻より後に編集されたセルはスキップ（高速化）。確認ダイアログあり。非同期実行でフロントエンドをブロックしない。
→ Null（副作用）
Options: `Fallback -> False`

### DocRefine[nb, cellIdx, opts]
選択セルのテキストを LLM で最小限の修正で校正する。元の意味・構成・文体・トーンを完全保持。Directive/Dictionary の指示を厳守。翻訳付きセルは翻訳も連鎖更新。idea/compute/メタセルは対象外。
→ Null（副作用）
Options: `Fallback -> False`
例: `DocRefine[EvaluationNotebook[], 3]`

### DocPolish[nb, cellIdx, opts]
選択セルのテキストを LLM でより完璧に書き直す。内容は保持しつつ文の構成・言い回しを大きく変更可。Directive/Dictionary 厳守。翻訳付きセルは翻訳も連鎖更新。idea/compute/メタセルは対象外。
→ Null（副作用）
Options: `Fallback -> False`
例: `DocPolish[EvaluationNotebook[], 3]`

### DocCompute[nb, cellIdx, opts]
計算モードのセルに対して LLM で Wolfram Language コードを生成・更新する。
→ Null（副作用）
Options: `Fallback -> False`

### DocSplitCell[nb, cellIdx]
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中は表示テキストと保存データを対応位置で分割し、プロンプトがあれば LLM で前半・後半用に再生成する。普通のセルはテキストを単純分割。
→ Null（副作用）

### DocMergeCells[nb, cellIdxs]
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し、最初のセルに統合する。モード・スタイルは最初のセルを維持。
→ Null（副作用）

### DocInsertNote[nb]
カーソル位置に Note スタイルのセルを挿入する。ノートブックに `"Note"` スタイル定義があればそれを使用、なければ内蔵定義（薄黄色背景、左側琥珀色枠線）を使用。エクスポート時は出力から除外される。
→ Null（副作用）

### DocInsertDictionary[nb]
カーソル位置に Dictionary スタイルのセルを挿入する。翻訳時の用語対応を指定する。エクスポート時は除外。
→ Null（副作用）
形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語1", "term1", "文脈"}, ...}` — 1行目はヘッダー（`<<>>`で囲む）、2行目以降が用語対応。

### DocInsertDirective[nb]
カーソル位置に Directive スタイルのセルを挿入する。展開・翻訳・同期実行時に LLM が順守すべき指示を記載する。複数配置可能。エクスポート時は除外。
→ Null（副作用）

### DocInsertBibliography[nb]
カーソル位置に Bibliography スタイルのセルを挿入する。参考文献リストを管理する。エクスポート時は除外。
→ Null（副作用）
形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}` — 本文中の `<<cite:key>>` がエクスポート時に自動変換される。

### DocEditFigureMeta[nb, cellIdx]
画像セルの図メタデータ（ラベル・キャプション）を編集するダイアログを表示する。本文中の `<<fig:label>>` がエクスポート時に自動変換される。ラベルは `figLabel` タグ、キャプションは `figCaption` タグに保存。
→ Null（副作用）

### DocEditRefSources[nb, cellIdx]
セルの依存資料（PDF パス・参照ページ番号）を編集するダイアログを表示する。LaTeX/Math エクスポート時に該当ページのみ LLM に送付してトークン消費を削減する。`refSources` タグに保存。
→ Null（副作用）

### DocAutoInsertCitations[nb]
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し、LLM が本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliography セルが存在しなければ末尾に自動生成する。
→ Null（副作用）

### DocExportMarkdown[nb, opts]
ノートブックを Markdown 形式でエクスポートする。
出力先: `NotebookDirectory[] / <ノートブック名>_md/`
除外: Note/Dictionary/Directive/Bibliography スタイルのセル。
画像: ラスター→PNG、ベクター/計算結果→PDF。
`<<fig:label>>` と `<<cite:key>>` は自動変換。Input セルはコードブロック、数式は TeX に変換。
→ Null（副作用）
Options: `"MathFormat" -> False` （Trueで LLM による数式自動フォーマット）

### DocExportLaTeX[nb, opts]
ノートブックを LaTeX 形式でエクスポートする。
出力先: `NotebookDirectory[] / <ノートブック名>_LaTeX/`
除外: Note/Dictionary/Directive/Bibliography スタイルのセル。
`<<fig:label>>` → `\ref{fig:label}`、`<<cite:key>>` → `\cite{key}` に変換。
→ Null（副作用）
Options: `"MathFormat" -> False` （Trueで LLM による数式自動フォーマット）

### DocExportWord[nb, opts]
ノートブックを Word (.docx) 形式でエクスポートする。内部で `DocExportMarkdown` を実行し Pandoc で変換する。Pandoc のインストールが必要。
出力先: `NotebookDirectory[] / <ノートブック名>_md/<ノートブック名>.docx`
→ Null（副作用）
Options: `"ReferenceDoc" -> None` （テンプレート .docx ファイルのパス）、`"MathFormat" -> False`

### ShowDocPalette[]
ドキュメント作成用パレットを表示する。パレットから全機能（展開・切替・翻訳・同期・エクスポート等）を操作できる。
→ Null（副作用）

## パブリック変数

### $DocTranslationLanguage
型: String, 初期値: `$Language` が英語以外なら `"English"`、英語なら `"Japanese"`
翻訳先の言語名。ユーザーが任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`

## 依存パッケージの役割

`NBAccess`` — セルの読み書き・TaggingRules アクセス・LLM ルーティングをすべて担う。documentation は `NBAccess`` の公開 API のみを使用し、セル内容に直接アクセスしない。
`ClaudeCode`` — LLM コールバック、ポーリング tick 共有、フォールバック LLM 選択、UI 優先モード制御を提供する。