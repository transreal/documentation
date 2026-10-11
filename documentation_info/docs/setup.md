# documentation パッケージ インストール手順書

macOS/Linux ではパス区切りやシェルコマンドを適宜読み替えてください。

---

## 動作要件

| 項目 | バージョン / 条件 |
|------|-----------------|
| Mathematica | 13.0 以上 |
| OS | Windows 11（64-bit） |
| 依存パッケージ | NBAccess, claudecode |
| 外部サービス | Anthropic Claude API（LLM 機能に必要） |
| Pandoc | 2.0 以上（MS-Word 形式でのエクスポートに必要） |

---

## 依存パッケージの確認

`documentation` パッケージは以下の 2 つのパッケージに依存します。  
先にこれらをインストールしてください。

- **NBAccess** — [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)
- **claudecode** — [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)

各パッケージのインストール手順は、それぞれのリポジトリの `setup.md` を参照してください。

---

## インストール手順

### 1. リポジトリの取得

[https://github.com/transreal/documentation](https://github.com/transreal/documentation) から  
`documentation.wl` を取得し、`$packageDirectory` に配置します。

```
例: C:\Users\<ユーザー名>\Documents\WolframPackages\documentation.wl
```

#### 論文 PDF 逆変換サブモジュール（任意）

論文 PDF をノートブックに逆変換する機能（`DocImportPaper` 等）を使う場合は、  
[https://github.com/transreal/documentation_paper2nb](https://github.com/transreal/documentation_paper2nb) から  
`documentation_paper2nb.wl` を取得し、`documentation.wl` と同じ `$packageDirectory` に配置してください。

`documentation.wl` はロード時に `$packageDirectory` 内の `documentation_paper2nb.wl` を自動検出して読み込みます。  
ファイルが存在しない場合はエラーにはならず、当該機能のみが無効化されます（コンソールにスキップメッセージが表示されます）。  
この機能を使わない場合は配置不要です。

### 2. $packageDirectory の確認

Mathematica 上で以下を実行し、`$packageDirectory` が設定済みであることを確認します。

```mathematica
$packageDirectory
```

未設定の場合は、`claudecode` パッケージの手順に従って `claudecode.wl` を先にロードしてください。  
`claudecode` が有効な環境では `$Path` は自動的に設定されます。

### 3. $Path の手動設定（claudecode を使用しない場合）

```mathematica
If[!MemberQ[$Path, $packageDirectory],
  AppendTo[$Path, $packageDirectory]
]
```

**注意**: `$packageDirectory` 自体を `$Path` に追加します。  
`"C:\\path\\to\\documentation"` のようにサブディレクトリを指定しないでください。

### 4. Pandoc のインストール（MS-Word 形式でのエクスポートに必要）

`DocExportWord[]` を使用して `.docx` 形式でエクスポートする場合は、**Pandoc** が必要です。  
Pandoc を使用しない場合（Markdown・LaTeX エクスポートのみ）はこの手順を省略できます。

#### インストール方法

**Windows（winget を使用）:**

```powershell
winget install --id JohnMacFarlane.Pandoc
```

**Windows（インストーラーを使用）:**

[https://pandoc.org/installing.html](https://pandoc.org/installing.html) から最新版のインストーラーをダウンロードして実行してください。

**macOS（Homebrew を使用）:**

```bash
brew install pandoc
```

**Linux（apt を使用）:**

```bash
sudo apt-get install pandoc
```

#### インストールの確認

ターミナル（PowerShell または コマンドプロンプト）で以下を実行し、バージョンが表示されれば正常にインストールされています。

```
pandoc --version
```

インストール後、Mathematica から以下を実行して Word 形式でのエクスポートを確認できます。

```mathematica
DocExportWord[EvaluationNotebook[]]
```

`NotebookDirectory[]` 以下に `<ノートブック名>_md/<ノートブック名>.docx` が生成されれば成功です。

---

## パッケージの読み込み

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["Documentation`", "documentation.wl"]
]
```

依存パッケージ（`NBAccess`・`ClaudeCode`）は `documentation.wl` 内で自動的に `Needs` されます。  
`documentation_paper2nb.wl` が `$packageDirectory` に存在する場合は、続けて自動的にロードされます。

---

## API キーの設定

`documentation` パッケージの LLM 機能（アイデア展開・翻訳・計算・論文 PDF 逆変換）は  
`NBAccess` および `claudecode` 経由で Anthropic Claude API を呼び出します。  
テキスト変換系の LLM 呼び出し（展開・翻訳・更新・分割など）は内部で「PlainText 応答契約」に統一されており、  
応答が不正な形式の場合は 1 回だけ再問合せしたうえで型付き `Failure` を返します（利用者側での追加設定は不要です）。

API キーの設定は `claudecode` パッケージの手順に従ってください。  
設定済みであれば追加の操作は不要です。

主要な設定変数（任意）:

```mathematica
(* 翻訳先言語の変更（デフォルト: "English" または "Japanese"） *)
$DocTranslationLanguage = "French"
```

---

## 動作確認

### パレットの表示

```mathematica
ShowDocPalette[]
```

ドキュメント作成用パレットが表示されれば正常にロードされています。

### アイデア展開のテスト

```mathematica
(* カレントノートブックの 1 番目のセルを展開 *)
DocExpandIdea[EvaluationNotebook[], 1]
```

LLM によるパラグラフ展開が実行されれば動作確認完了です。

### 表示切替のテスト

```mathematica
(* アイデア ↔ パラグラフの表示を切り替え *)
DocToggleView[EvaluationNotebook[], 1]
```

図セルの翻訳版（図中の文字を翻訳先言語に置き換えた図）が保存されている場合も、`DocToggleView` でテキストセルの翻訳と同じように原語図 ↔ 翻訳図を切り替えられます。切替時には、表示中の図が相手側のタグに自動保存されます。

### コード計算のテスト

```mathematica
(* カレントノートブックの 1 番目のセルをコード計算モードで実行 *)
DocCompute[EvaluationNotebook[], 1]
```

プロンプトテキストをもとに LLM が実行可能なコードを生成し、セルが計算モード（左側にオレンジの枠線）に切り替われば動作確認完了です。  
LLM は生成コードを 1 つのコードブロックにまとめて出力します。ファイル参照には `FileNameJoin` によるパス構築が自動で適用されます。  
計算結果を削除してプロンプト状態に戻すには、パレットの「×計算」ボタンを使用します。  
プロンプト状態に戻した後はプロンプトを編集して再度「計算」ボタンを押すことで、再生成できます。

`DocCompute` は `Fallback -> True` オプションを受け付けます。API が利用制限に達した場合にフォールバックモデルを試みる場合に指定してください（デフォルト: `False`）。

複数セルを選択した状態でパレットの「計算」ボタンを押すと、選択セルを順番に連鎖実行します。  
同様に「×展開」「×翻訳」ボタンで選択セルの展開結果・翻訳結果をまとめて削除できます。図セルの翻訳をクリアした場合は、翻訳図表示中なら原語図に戻したうえで図の翻訳タグも削除されます。

### 論文 PDF 逆変換のテスト（documentation_paper2nb.wl 導入時のみ）

パレットの「← 論文PDF」（英語表示では "← Paper PDF"）ボタンを押すと、ファイル選択ダイアログが表示され、  
選択した論文 PDF を解析してノートブックへ逆変換します（`DocImportPaper` に相当）。  
処理には数分かかりカーネルを占有するため、実行中は他の操作を控えてください。  
`documentation_paper2nb.wl` を配置していない場合、このボタンおよび関連機能は利用できません。

個別ページの構造解析や計算抽出を単独で試す場合は、以下の診断用関数を直接呼び出せます。

```mathematica
(* PDF の 1 ページを構造解析してブロックリストを返す *)
DocPaperAnalyzePage["C:/papers/example.pdf", 1]

(* 論文全文から再現可能な計算・アルゴリズムを抽出する *)
DocPaperExtractComputations["C:/papers/example.pdf"]
```

直近の `DocImportPaper` / `DocPaperAnalyzePage` / `DocPaperExtractComputations` の中間結果（ブロック・セル構造など）は `$DocPaperLastAnalysis` に保持されます。デバッグや部分再利用に活用できます。

また、LaTeX 数式文字列を TraditionalForm ボックスに変換する `DocPaperTeXToBoxes`、および `$...$` や `\(...\)` を含む文字列をインライン数式セル埋め込みの TextData に変換する `DocPaperTextToTextData` も公開されており、ノートブック編集スクリプト等から利用できます。

`DocImportPaper` は、LLM サーバへの接続失敗（URL の設定誤りやサーバ停止など）が 2 ページ連続で発生すると、残りのページを空回りさせずに処理を中断します（`DocImportPaper::abort` メッセージが表示されます）。ローカル LLM サーバを使う場合は、事前にサーバが起動していることを確認してください。また、画像入力に対応しないモデル/サーバに接続した場合は、そのセッション中は以後のページで画像付き解析を自動的に省略し、テキストのみで解析を続行します。

---

## エクスポート時の図サイズについて

Markdown エクスポート（`DocExportMarkdown`）では、図は `{#fig-label width=100%}` 形式で出力され、表示幅いっぱいに展開されます。

LaTeX エクスポート（`DocExportLaTeX`）では、図は `[!htbp]` 配置指定と高さ制限付きで、`\includegraphics[width=\textwidth]{...}` を用いて本文中の参照位置付近に出力されます。付録の図一覧のように図をページ全体の高さで独立ページに配置したい場合は、対象の画像セルの `TaggingRules` に `documentation/figFullPage -> True` を設定してください。`[p]` 配置指定の全ページ図として出力されます。

翻訳モードでのエクスポートでは、図キャプションは LLM で翻訳する代わりに、図セルに保存された翻訳先言語のキャプション（`figCaptionTranslation`）が使われます。

LaTeX プリアンブルは、pLaTeX/upLaTeX（`jsarticle` + `dvipdfmx`、Overleaf の和文設定）と pdfLaTeX（`CJKutf8`）のどちらでコンパイルしても正しく組版できるよう、`iftex` パッケージで自動的に切り替わります。生成される `.tex` ファイルはどちらの TeX 処理系でもそのまま使用できます。

本文中の Unicode 数学記号（ギリシャ文字・上付き/下付き文字・∈ × ⌈ 等）や `_ ^ # % &` などの LaTeX 特殊文字は、LLM を使わない決定的な変換で自動的に LaTeX 記法へエスケープされます（`\cite{}` `\ref{}` のキーも ASCII に正規化されます）。

数式部分の検出は、本文をトークンに分けて各トークンに役割（数式・地の文など）を付け、数式と判断した区間だけを `$...$` で囲む方式です。変数・ギリシャ文字・上付き/下付き・演算子で構成される式、中身が式の括弧（`(c, e)`、`{0, 1}`、`(SSR)*` など）、関数適用や後置記号（`'` `*` `^`）付きの語を数式として扱います。一方、英単語を含む括弧、列挙ラベル `(a)` `(ii)`、和文に密着した数（`1類`、`4タイル`）、ファイル名や複合語（`deg4-DB`、`L-system`）、英文の冠詞 `a` / `I` や頭文字は地の文のままにします。引用・参照・既存の `$...$` / `\(...\)` は保護され、URL は `\url{}` になります。

`DocExportMarkdown`・`DocExportLaTeX`・`DocExportWord` はいずれも `"MathFormat" -> True` オプションを受け付けます。このオプションを指定すると、決定的な変換に加えて LLM による数式の自動整形を追加で行います（デフォルト: `False`）。

---

## よくあるトラブル

| 症状 | 対処法 |
|------|--------|
| `Needs::nocntxt` エラー | `$Path` に `$packageDirectory` が含まれているか確認する |
| `NBAccess` が見つからない | NBAccess を先にロードまたは `$Path` を確認する |
| LLM が応答しない | `claudecode` の API キー設定を確認する。`NBAccess\`$NBLLMLastError` に実エラー文が記録される |
| 文字化けが発生する | `Block[{$CharacterEncoding = "UTF-8"}, ...]` でロードしているか確認する |
| `DocExportWord` が失敗する | Pandoc がインストールされているか確認する（`pandoc --version`） |
| 計算モードのセルに再度「計算」を適用できない | パレットの「×計算」でプロンプト状態に戻してから再実行する |
| LaTeX エクスポートした図がページ全体に落ちて印刷で読めない | 図セルの `TaggingRules` に `documentation/figFullPage -> True` を設定し、独立ページの全ページ図として出力する |
| LaTeX 出力で数式にすべきでない語が数式化された、または数式が地の文のままになった | 数式検出は決定的な規則で行われる。必要に応じて本文側で `$...$` を明示するか、`"MathFormat" -> True` を指定して LLM 整形を併用する |
| コンソールに「documentation_paper2nb.wl が見つからないためスキップ」と表示される | 論文 PDF 逆変換機能を使わない場合は無視してよい。使う場合は `documentation_paper2nb.wl` を `$packageDirectory` に配置する |
| `DocImportPaper::abort` が表示され処理が中断する | LLM サーバへの接続失敗が 2 ページ連続で発生した状態。サーバの起動状況や URL 設定を確認してから再実行する |

---

## 関連リンク

- documentation リポジトリ: [https://github.com/transreal/documentation](https://github.com/transreal/documentation)
- documentation_paper2nb リポジトリ（論文 PDF 逆変換サブモジュール）: [https://github.com/transreal/documentation_paper2nb](https://github.com/transreal/documentation_paper2nb)
- NBAccess リポジトリ: [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)
- claudecode リポジトリ: [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)