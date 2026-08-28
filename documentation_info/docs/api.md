# Documentation` API Reference

`Documentation`` パッケージ。アウトラインプロセッサ拡張：アイデア → パラグラフ展開システム。
依存: [NBAccess`](https://github.com/transreal/NBAccess), [ClaudeCode`](https://github.com/transreal/claudecode)
ロード: `Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]`

## セル展開・切替

### DocExpandIdea[nb, cellIdx, opts]
指定セルのアイデアテキストを LLM でパラグラフに展開する。既にパラグラフ表示中なら現在のパラグラフを尊重しつつインプレース更新する。元のアイデアは TaggingRules に保存される。Note/Dictionary/Directive セルは対象外。
→ $Failed（失敗時）
Options: Fallback -> False (True でフォールバック LLM を使用)

### DocToggleView[nb, cellIdx] → String | $Failed
セルの表示モードを循環切替する。モード別動作: 通常セルはアイデア ↔ パラグラフ（→ 翻訳があれば翻訳へ）、mode="translated" セルは元テキスト ↔ 翻訳、mode="compute"/"computePrompt" セルはコード ↔ プロンプト、mode="figClean"/"figOutline" セルは手書き ↔ 清書済み図（`iDocToggleFigureClean` に委譲）。現在表示中の内容（編集済みでも）を保存してから切り替える。編集済みの場合（figClean/compute を除く）は他レイヤーをバックグラウンドで LLM 同期する。Note/Dictionary/Directive セルは対象外。

### DocSplitCell[nb, cellIdx]
カーソル位置でセルを前半・後半に分割する。パラグラフ/翻訳表示中は表示テキストと保存データを対応位置で分割し、プロンプトがあれば LLM で前半・後半用に再生成する。普通のセルはテキストを単純に分割する。

### DocMergeCells[nb, cellIdxs]
複数セルを単一セルに合併する。テキスト・プロンプト・翻訳をそれぞれ結合し最初のセルに統合する。モード・スタイルは最初のセルを維持する。

## テキスト品質向上

### DocRefine[nb, cellIdx, opts]
選択セルのテキストを LLM で校正する。文法的・表現上の不自然さを最小限の修正で訂正し、元の意味・構成・文体・トーンを完全に保持する。Directive/Dictionary セルの指示は厳守する。翻訳付きセルの場合は翻訳も連鎖更新する。対象外: idea モード、compute モード、メタセル。
→ $Failed（失敗時）
Options: Fallback -> False (True でフォールバック LLM を使用)

### DocPolish[nb, cellIdx, opts]
選択セルのテキストを LLM でより完璧に書き直す。内容（情報・主旨・意図）は保持しつつ文の構成や言い回しを必要に応じて大きく変更する。Directive/Dictionary セルの指示は厳守する。翻訳付きセルの場合は翻訳も連鎖更新する。対象外: idea モード、compute モード、メタセル。
→ $Failed（失敗時）
Options: Fallback -> False (True でフォールバック LLM を使用)

## 翻訳・同期

### DocTranslate[nb, cellIdx, opts]
セルのテキストを翻訳する。翻訳結果は TaggingRules に保持し DocToggleView で切替可能。パラグラフモードと普通のセル（モード未設定）が対象。アイデアモード・翻訳表示中は対象外。
→ $Failed（失敗時）
Options: Fallback -> False (True でフォールバック LLM を使用)

### DocSync[nb, cellIdx, opts]
現在の指示(Directive)・辞書(Dictionary)の変更を単一セルに反映する。idea モードならパラグラフを再生成（翻訳があれば連鎖更新）。
→ $Failed（失敗時）
Options: Fallback -> False (True でフォールバック LLM を使用)

### DocSyncAll[nb, opts]
ノートブック内の全 paragraph/idea セルを現在の指示・辞書・プロンプトに従って一括再生成する。翻訳があれば連鎖的に翻訳も更新する。指示/辞書セルの最終更新時刻より後に編集されたセルはスキップ（高速化）。確認ダイアログを表示後、非同期でフロントエンドをブロックせず処理する。
Options: Fallback -> False (True でフォールバック LLM を使用)

## 計算モード

### DocCompute[nb, cellIdx, opts]
セルのテキスト（自然言語の計算依頼）を LLM で Wolfram Language コードに変換し、Input セル（compute モード）として書き込む。元のプロンプトは TaggingRules に保存され、DocToggleView でコード ↔ プロンプト表示を切替できる。既に compute モード（コード表示中）のセルには適用不可（先に DocToggleView でプロンプト表示に戻す必要がある）。対象外: メタセル。
→ $Failed（失敗時）
Options: Fallback -> False (True でフォールバック LLM を使用)

## セル挿入

### DocInsertNote[nb]
現在のカーソル位置に Note スタイルのセルを挿入する。ノートブックにスタイル "Note" が定義済みならそれを使用し、なければカスタム定義の Note セルを挿入する。

### DocInsertDictionary[nb]
現在のカーソル位置に Dictionary スタイルのセルを挿入する。翻訳時に LLM が遵守する用語対応を指定する。
形式: `{{<<Japanese>>, <<English>>, <<Context>>}, {"用語1", "term1", "文脈"}, ...}`（1行目はヘッダー、2行目以降が Context における用語対応）

### DocInsertDirective[nb]
現在のカーソル位置に Directive スタイルのセルを挿入する。展開・翻訳・同期の実行時に LLM が順守すべき指示を記載する。複数の Directive セルを配置可能。

### DocInsertBibliography[nb]
現在のカーソル位置に Bibliography スタイルのセルを挿入する。参考文献リストを管理する。
形式: `{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {"key", "author", "year", "title"}, ...}`
本文中で `<<cite:key>>` と記述するとエクスポート時に自動変換される。

## メタデータ編集

### DocEditFigureMeta[nb, cellIdx]
画像セルの図メタデータを編集するダイアログを表示する。ラベル（参照用キー）とキャプションを設定する。本文中で `<<fig:label>>` と記述するとエクスポート時に自動変換される。図セルの TaggingRules `documentation/figFullPage -> True` を設定すると LaTeX エクスポート時に独立ページ（`[p]`）の全ページ図になる（付録の図一覧など向け）。

### DocEditRefSources[nb, cellIdx]
セルの依存資料を編集する。アタッチされた PDF のうちそのセルの内容生成に使われた資料と参照ページ番号を設定する。LaTeX+Math エクスポート時に該当ページのみを LLM に送付してトークン消費を削減する。

### DocAutoInsertCitations[nb]
ノートブック内の全セルに自動引用を挿入する。依存資料（refSources）から文献リストを構築し LLM が本文中の適切な位置に `<<cite:key>>` マーカーを挿入する。Bibliography セルが存在しなければ末尾に自動生成する。

## エクスポート

### DocExportMarkdown[nb, opts]
ノートブックを Markdown 形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_md/`。Note/Dictionary/Directive/Bibliography セルは出力から除外される。画像はラスター→PNG、ベクター/計算結果→PDF で保存。`<<fig:label>>` と `<<cite:key>>` は自動変換される。Input セルはコードブロック、数式は TeX に変換される。
Options: "MathFormat" -> False (True で LLM による数式自動フォーマット)

### DocExportLaTeX[nb, opts]
ノートブックを LaTeX 形式でエクスポートする。出力先: `NotebookDirectory[]/<ノートブック名>_LaTeX/`。Note/Dictionary/Directive/Bibliography セルは出力から除外される。画像はラスター→PNG、ベクター/計算結果→PDF で保存。`<<fig:label>>` は `\ref{fig:label}` に、`<<cite:key>>` は `\cite{key}` に変換される。本文中の Unicode 数学記号（添字・ギリシャ文字・∈ → × ⌈ 等）は決定的に LaTeX 数式へ変換し、`_ ^ # % &` 等はエスケープする（LLM 不使用）。`\cite`/`\ref` のキーは ASCII に正規化される。プリアンブルは pLaTeX/upLaTeX（jsarticle+dvipdfmx, Overleaf の和文設定）と pdfLaTeX（CJKutf8）の両方で通るよう `iftex` で自動切替する。図は `[!htbp]` + 高さ制限で参照位置付近に配置。図セルの TaggingRules `documentation/figFullPage -> True` で独立ページ（`[p]`）の全ページ図にできる（付録の一覧図など）。
Options: "MathFormat" -> False (True で LLM による数式自動フォーマットを追加で行う)

### DocExportWord[nb, opts]
ノートブックを Word (.docx) 形式でエクスポートする。内部で DocExportMarkdown を実行し Pandoc で .docx に変換する。Pandoc がインストールされている必要がある。出力先: `NotebookDirectory[]/<ノートブック名>_md/<ノートブック名>.docx`
Options: "ReferenceDoc" -> None (テンプレート .docx ファイルのパス), "MathFormat" -> False (True で LLM による数式自動フォーマット)

## パレット

### ShowDocPalette[] → NotebookObject
ドキュメント作成用パレットを表示する。

## 変数

### $DocTranslationLanguage
型: String, 初期値: $Language が英語以外なら "English"、英語なら "Japanese"
翻訳先の言語名。ユーザーが任意の言語名に変更可能。
例: `$DocTranslationLanguage = "French"`