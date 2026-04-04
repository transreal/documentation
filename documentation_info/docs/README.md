# documentation

Mathematica ノートブック上でアイデアメモから文章品質のパラグラフを生成するドキュメント作成支援パッケージです。翻訳辞書・LLM 指示・文献管理・図の引用、Markdown・LaTeX・MS-Word へのエクスポート（試験的）など、執筆から出版まで一貫したワークフローを提供します。

## 設計思想と実装の概要

### 設計思想: アウトラインプロセッサとしての Mathematica ノートブック

本パッケージは、Mathematica ノートブックを「アウトラインプロセッサ」として拡張することを目的として設計されています。従来、ノートブックは計算結果や数式を記録する場として使われてきましたが、`documentation` パッケージはノートブックを文章執筆の場として再定義します。

執筆の現場では、まず断片的なアイデアや箇条書きのメモを書き、それを推敲して文章に仕上げるという二段階のプロセスが一般的です。本パッケージはこの「アイデア → パラグラフ」という変換フローを LLM によって自動化し、さらにパラグラフと翻訳の双方向同期まで含めた一貫したワークフローを提供します。

### アーキテクチャの核心: ドキュメント作成環境としての設計

パッケージ全体は、**「書く」という行為のすべてのフェーズを一つのノートブック内で完結させる**ことを目標に設計されています。

#### アイデア・パラグラフ・翻訳の三モード切替

各セルは「アイデア（プロンプト）」「パラグラフ」「翻訳」の 3 つのモードを持ちます。書き手はアイデアとして断片的なメモを書き、**▶ 展開** ボタンで LLM にパラグラフを生成させます。生成後も元のアイデアは内部に保持され、**↔ 切替** でいつでも行き来できます。

**▶ 展開** ボタンは初回展開だけでなく、**既にパラグラフ展開済みのセルに対しても再度押すことで、現在のパラグラフ・Directive セルの指示・文脈を踏まえてパラグラフをインプレース更新します**。Directive や Dictionary の内容を追加・変更した後に既存パラグラフを一括改善したい場合にも活用できます。

パラグラフが完成したら **» 翻訳** で指定言語に翻訳し、**翻訳表示** に切り替えます。**» 翻訳** ボタンも同様に、**既に翻訳済みのセルに対して再度押すと、現在のパラグラフから翻訳を再生成します**。Dictionary や Directive の内容を更新した後に翻訳をやり直したい場合に便利です。元文を修正した場合は **⇌ 同期** を押すだけで翻訳が自動更新されます。逆に翻訳を編集して同期すると、その変更が元のパラグラフに逆反映されます。この「アイデア → パラグラフ → 翻訳」の往復こそが本パッケージの中心的なワークフローです。

| モード | 枠線色 | 用途 |
|--------|--------|------|
| アイデア | 琥珀色 | 展開前のメモ・プロンプト |
| パラグラフ | 緑 | LLM が生成した本文 |
| 翻訳 | 青 / 水色 | 翻訳テキストと元文の対比表示 |
| 計算 | オレンジ | LLM が生成した実行可能コード |

#### コード生成（計算モード）

セルに書いたプロンプトから、LLM が実行可能な Wolfram Language コードを自動生成する **計算モード** を備えています。生成されたコードはセルにオレンジ色の枠線で表示され、パレットの **↔ 切替** でプロンプト表示に戻して再編集・再生成が可能です。

#### 図の引用と参考文献リストの自動生成

画像セルには**図ラベルとキャプション**を付与でき、本文中で `<<fig:label>>` と記述するだけでエクスポート時に自動的に図番号参照へ変換されます。参考文献は **Bibliography セル**で一元管理し、本文中の `<<cite:key>>` マーカーが Markdown では `[key]`、LaTeX では `\cite{key}` に自動変換されます。PDF 資料から依存情報を記録して文献リストを自動構築する**自動引用挿入**機能も備えています。

#### 数式の高再現度 LaTeX エクスポート

`DocExportLaTeX[]` は Mathematica ノートブック内の数式を LaTeX コードに変換してエクスポートします。`"MathFormat" -> True` オプションを指定すると LLM が数式を対象フォーマット向けに自動フォーマットし、再現度の高い LaTeX 出力を生成します。コードブロックは `lstlisting` 環境で出力され、Note・Directive・Dictionary などのメタセルはエクスポート対象から自動除外されます。

#### 執筆指示と用語辞書のノートブック内管理

**Directive セル**にはノートブック全体の LLM 指示（文体・表記ルール等）を記載でき、すべての展開・翻訳・同期・計算操作に自動適用されます。**Dictionary セル**は翻訳時の用語対応を管理し、技術用語や固有名詞を一貫した訳語に統一します。これらのメタセルはエクスポート対象外であり、最終出力には含まれません。

### セル状態管理: TaggingRules による非破壊的なデータ保持

アイデアテキストを書き換えてパラグラフを生成するのではなく、**現在表示中でない内容を TaggingRules に格納し、切替時に入れ替える**という方式を採用しています。翻訳テキストも同様に保持されるため、一度翻訳したセルは LLM を再呼び出しすることなく瞬時に切替表示できます。ソーステキストが変わった場合のみ再翻訳が走る仕組みです。

### 非同期実行と完了コールバックチェーン

LLM の呼び出しはすべて非同期で実行され、カーネルをブロックしません。複数セルの一括展開・翻訳・計算時は、完了コールバック内で `RunScheduledTask` を使って次のセルの処理を連鎖させることで、逐次処理を実現しています。

### 責務分離について

セル内容へのアクセスは [NBAccess](https://github.com/transreal/NBAccess) の公開 API 経由に限定し、LLM 呼び出しも `NBAccess``NBCellTransformWithLLM` 経由に統一しています。これにより、プライバシーレベルに応じた LLM の自動選択やビジュアル要素の競合を防いでいます。モデル選択・エフォートレベルなどの設定は [claudecode](https://github.com/transreal/claudecode) パッケージと共有されます。

---

## 詳細説明

### 動作環境

| 項目 | バージョン / 条件 |
|------|-----------------|
| Mathematica | 13.0 以上 |
| OS | Windows 11（64-bit） |
| 依存パッケージ | [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode) |
| 外部サービス | Anthropic Claude API（LLM 機能に必要） |
| Pandoc | 2.0 以上（MS-Word 形式でのエクスポートに必要） |

### インストール

#### 1. 依存パッケージのインストール

`documentation` パッケージは以下の 2 つのパッケージに依存します。先にインストールしてください。

- **NBAccess**: [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)
- **claudecode**: [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)

#### 2. パッケージファイルの配置

[https://github.com/transreal/documentation](https://github.com/transreal/documentation) から `documentation.wl` を取得し、`$packageDirectory` に配置します。

#### 3. `$Path` の設定

claudecode を使用している場合、`$Path` は自動的に設定されます。手動で設定する場合は以下を実行します。

```mathematica
If[!MemberQ[$Path, $packageDirectory],
  AppendTo[$Path, $packageDirectory]
]
```

**注意**: `$packageDirectory` 自体を `$Path` に追加してください。パッケージ固有のサブディレクトリを指定しないでください。

#### 4. Pandoc のインストール（MS-Word エクスポートに必要）

`DocExportWord[]` を使用して `.docx` 形式でエクスポートする場合は Pandoc が必要です。Markdown・LaTeX エクスポートのみであればこの手順は省略できます。詳細は `setup.md` を参照してください。

#### 5. パッケージの読み込み

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["Documentation`", "documentation.wl"]
]
```

依存パッケージ（`NBAccess`・`ClaudeCode`）は `documentation.wl` 内で自動的に `Needs` されます。パッケージのロードと同時にパレットが自動表示されます。

### クイックスタート

```mathematica
(* 1. パッケージをロード（パレットが自動表示される） *)
Block[{$CharacterEncoding = "UTF-8"},
  Needs["Documentation`", "documentation.wl"]
]

(* 2. 翻訳先言語を設定（任意。デフォルトは "English" または "Japanese"） *)
$DocTranslationLanguage = "English"

(* 3. ノートブックのテキストセルにアイデアを書き、そのセルを選択した状態で展開 *)
nb = EvaluationNotebook[];
DocExpandIdea[nb, 1]

(* 4. アイデア表示とパラグラフ表示を切り替える *)
DocToggleView[nb, 1]

(* 5. パラグラフを翻訳する *)
DocTranslate[nb, 1]

(* 6. プロンプトから Wolfram Language コードを生成する *)
DocCompute[nb, 2]

(* 7. パレットを手動で再表示する（閉じてしまった場合） *)
ShowDocPalette[]
```

主要な設定変数:

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `$DocTranslationLanguage` | `"English"` または `"Japanese"` | 翻訳先言語名 |

### 主な機能

#### 基本ワークフロー

| 機能 | 説明 |
|------|------|
| **アイデア展開** | 断片的なメモを LLM で文章品質のパラグラフに変換。**展開済みセルに再実行するとパラグラフをインプレース更新** |
| **表示切替** | アイデア ↔ パラグラフ ↔ 翻訳 ↔ コードをワンクリックで循環切替 |
| **翻訳** | パラグラフを `$DocTranslationLanguage` 指定の言語に翻訳。**翻訳済みセルに再実行すると翻訳を再生成** |
| **同期** | 元文編集後に翻訳を最新化、翻訳編集後は逆反映 |
| **コード生成（計算）** | セルのプロンプトから実行可能な Wolfram Language コードを LLM で自動生成 |
| **セル分割** | カーソル位置でセルを前半・後半に分割 |
| **セル合併** | 複数選択セルを 1 つに統合 |

#### セル種別

| セル種別 | 挿入方法 | 用途 |
|----------|----------|------|
| **Note セル** | パレット「■ メモ」 | 執筆中のメモ・TODO。エクスポート対象外 |
| **Directive セル** | パレット「指示」 | 展開・翻訳・同期・計算時に LLM が順守すべき指示を記載 |
| **Dictionary セル** | パレット「辞書」 | 翻訳時の用語対応（技術用語・固有名詞）を指定 |
| **Bibliography セル** | パレット「文献」 | 参考文献リストを管理。エクスポート時に文献セクションとして出力 |

#### 図・文献管理

| 機能 | 説明 |
|------|------|
| **図メタデータ** | 画像セルにラベルとキャプションを設定し、本文から `<<fig:label>>` で参照 |
| **参照挿入** | 図・文献参照マーカー（`<<fig:...>>`・`<<cite:...>>`）をダイアログから挿入 |
| **依存資料** | セル生成に使用した PDF 資料とページ番号を記録 |
| **自動引用挿入** | 依存資料から文献リストを構築し、本文に引用マーカーを自動挿入 |

#### エクスポート（試験的）

| 形式 | 関数 | 備考 |
|------|------|------|
| Markdown | `DocExportMarkdown[nb]` | Note・Directive・Dictionary 等のメタセルを除外 |
| LaTeX | `DocExportLaTeX[nb]` | `lstlisting` 環境でコードブロックを出力。`"MathFormat" -> True` で数式を高再現度変換 |
| MS-Word | `DocExportWord[nb]` | Pandoc が必要。Markdown 経由で `.docx` を生成 |

すべてのエクスポートで `"MathFormat" -> True` オプションを指定すると、LLM が数式を対象フォーマット向けに自動フォーマットします。

エクスポートのセル除外設定: パレットの「除外切替」ボタンで任意のセルをエクスポート対象外に設定・解除できます。Note・Directive・Dictionary・Bibliography セルは常にエクスポート対象外です。

#### 関数一覧

| 関数 | 説明 |
|------|------|
| `DocExpandIdea[nb, cellIdx, opts]` | アイデアをパラグラフに展開。展開済みセルはインプレース更新（`Fallback -> True` でフォールバックモデル使用） |
| `DocToggleView[nb, cellIdx]` | アイデア / パラグラフ / 翻訳 / コードの循環切替。翻訳がある場合はパラグラフ→翻訳→アイデアの順に遷移 |
| `DocTranslate[nb, cellIdx, opts]` | セルを `$DocTranslationLanguage` に翻訳。翻訳済みセルは再翻訳（`Fallback -> True` でフォールバックモデル使用） |
| `DocSync[nb, cellIdx, opts]` | 現在表示テキストを基準に他コンポーネントを同期（`Fallback -> True` でフォールバックモデル使用） |
| `DocCompute[nb, cellIdx, opts]` | セルのプロンプトから実行可能な Wolfram Language コードを LLM で生成（`Fallback -> True` でフォールバックモデル使用） |
| `DocSplitCell[nb, cellIdx]` | カーソル位置でセルを前半・後半に分割。保存データも対応位置で分割 |
| `DocMergeCells[nb, cellIdxs]` | 複数セルを単一セルに合併。テキスト・プロンプト・翻訳をそれぞれ結合 |
| `DocInsertNote[nb]` | Note スタイルセルを挿入（エクスポート対象外） |
| `DocInsertDirective[nb]` | Directive スタイルセルを挿入。展開・翻訳・同期・計算時に LLM が参照 |
| `DocInsertDictionary[nb]` | Dictionary スタイルセルを挿入。翻訳時の用語対応を指定 |
| `DocInsertBibliography[nb]` | Bibliography スタイルセルを挿入。本文中の `<<cite:key>>` がエクスポート時に自動変換 |
| `DocEditFigureMeta[nb, cellIdx]` | 画像セルの図ラベル・キャプションを設定するダイアログを表示 |
| `DocEditRefSources[nb, cellIdx]` | セルの依存資料（PDF・参照ページ番号）を編集するダイアログを表示 |
| `DocAutoInsertCitations[nb]` | 依存資料から文献リストを構築し、本文に引用マーカーを自動挿入 |
| `DocExportMarkdown[nb, opts]` | Markdown エクスポート（`"MathFormat" -> True` で数式の高再現度変換） |
| `DocExportLaTeX[nb, opts]` | LaTeX エクスポート（`"MathFormat" -> True` で数式の高再現度変換） |
| `DocExportWord[nb, opts]` | MS-Word エクスポート（Pandoc 必要、`"ReferenceDoc" -> パス` でテンプレート指定） |
| `ShowDocPalette[]` | パレットを表示 |

#### パレットボタン一覧

| ボタン | 機能 |
|--------|------|
| ▶ 展開 | 選択セルのアイデアをパラグラフに展開。**展開済みセルは現在のパラグラフをインプレース更新**（複数選択時は逐次処理） |
| × 展開削除 | 展開データを削除してアイデアメモ状態に戻す（確認ダイアログあり） |
| » 翻訳 | 選択セルを翻訳。**翻訳済みセルは現在のパラグラフから再翻訳**（複数選択時は逐次処理） |
| × 翻訳削除 | 翻訳データを削除してパラグラフ状態に戻す（確認ダイアログあり） |
| 計算 | 選択セルのプロンプトから Wolfram Language コードを LLM で生成（複数選択時は逐次処理） |
| × 計算削除 | 生成されたコードを削除してプロンプト状態に戻す（確認ダイアログあり） |
| ↔ 切替 | 選択セルのアイデア / パラグラフ / 翻訳 / コードを循環切替 |
| ⇌ 同期 | 選択セルの各コンポーネントを同期 |
| 分割 | カーソル位置でセルを前後に分割 |
| 合併 | 複数選択セルを 1 つに統合 |
| ■ メモ | カーソル位置に Note セルを挿入（エクスポート対象外） |
| 指示 | LLM への指示を記載する Directive セルを挿入 |
| 辞書 | 翻訳用語辞書を管理する Dictionary セルを挿入 |
| 文献 | 参考文献リストを管理する Bibliography セルを挿入 |
| ■ 図メタ | 選択画像セルの図ラベル・キャプションを編集 |
| 参照挿入 | 図・文献参照マーカーをダイアログから挿入 |
| 除外切替 | 選択セルのエクスポート対象外フラグを設定 / 解除 |
| … 全プロンプト | ノートブック全体をアイデア表示に一括切替 |
| ¶ 全パラグラフ | ノートブック全体をパラグラフ表示に一括切替 |
| Â 全翻訳 | ノートブック全体を翻訳表示に一括切替 |
| → Markdown | ノートブックを Markdown 形式でエクスポート（試験的） |
| → LaTeX | ノートブックを LaTeX 形式でエクスポート（試験的） |
| → Word | ノートブックを MS-Word 形式でエクスポート（試験的・Pandoc 必要） |

#### $DocTranslationLanguage

翻訳先言語名を指定するグローバル変数です。デフォルトは `$Language` が英語以外なら `"English"`、英語なら `"Japanese"` です。任意の言語名（`"French"`, `"German"`, `"Spanish"` 等）を設定できます。

### ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| `api.md` | 全公開関数・変数のリファレンス、セルモードと TaggingRules 構造、エクスポートセルスタイルマッピングの詳細 |
| `user_manual.md` | ユーザーマニュアル、パレット操作ガイド、各関数の引数説明、典型的なワークフロー |
| `examples/example.md` | コード例集（パレット起動、展開、切替、翻訳設定、計算モード、複数セル操作、同期） |
| `setup.md` | インストール手順、動作要件、Pandoc のインストール方法、トラブルシューティング |

---

## 使用例・デモ

### パレットを開く

```mathematica
ShowDocPalette[]
```

### アイデアをパラグラフに展開する

```mathematica
nb = EvaluationNotebook[];
DocExpandIdea[nb, 2]
```

セル 2 のアイデアテキストが LLM によって文章品質のパラグラフに書き換えられます。

### 展開済みパラグラフをインプレース更新する

```mathematica
(* Directive セルの指示を追加・変更した後、既存パラグラフを改めて更新する *)
nb = EvaluationNotebook[];
DocExpandIdea[nb, 2]
```

セル 2 がすでに展開済みの場合、**▶ 展開** を再度実行すると現在のパラグラフ・Directive セルの指示・文脈を踏まえてパラグラフがインプレース更新されます。

### パラグラフをアイデア表示に戻す（トグル）

```mathematica
DocToggleView[EvaluationNotebook[], 2]
```

### プロンプトから Wolfram Language コードを生成する

```mathematica
nb = EvaluationNotebook[];
DocCompute[nb, 4]
```

セル 4 に記述されたプロンプトテキストを LLM に送信し、実行可能な Wolfram Language コードを生成します。生成されたコードはセルに書き込まれ、計算モード（オレンジ枠線）で表示されます。

### 計算モードとプロンプトモードを切り替える

```mathematica
DocToggleView[EvaluationNotebook[], 4]
```

セル 4 が計算結果（コード）表示中であればプロンプト表示に、プロンプト表示中であれば計算モードに切り替わります。コード表示中のセルに直接 `DocCompute` を再適用することはできません。プロンプト表示に戻してから再度 `DocCompute` を実行してください。

### フォールバックモデルを許可して計算する

```mathematica
DocCompute[EvaluationNotebook[], 4, Fallback -> True]
```

### フランス語への翻訳を設定してから翻訳する

```mathematica
$DocTranslationLanguage = "French";
DocTranslate[EvaluationNotebook[], 3]
```

### 翻訳済みセルの翻訳を再生成する

```mathematica
(* Dictionary セルの用語対応を更新した後、翻訳をやり直す *)
DocTranslate[EvaluationNotebook[], 3]
```

セル 3 がすでに翻訳済みの場合、**» 翻訳** を再度実行すると現在のパラグラフから翻訳を再生成します。

### 翻訳を編集してパラグラフに逆反映する

```mathematica
(* 翻訳表示中に同期すると、翻訳の編集内容がパラグラフに反映される *)
DocSync[EvaluationNotebook[], 4]
```

### フォールバックモデルを許可して同期する

```mathematica
DocSync[EvaluationNotebook[], 4, Fallback -> True]
```

### Directive セルで LLM に執筆指示を与える

ノートブックに Directive セルを挿入し、以下のような指示を記載します。展開・翻訳・同期・計算のすべての LLM 呼び出しでこの指示が自動的に参照されます。

```
- 専門用語は必ず太字にする
- 文末は「です・ます調」で統一する
```

### Dictionary セルで用語翻訳を統一する

Dictionary セルにテーブル形式で用語対応を記載します。翻訳時に自動参照され、指定した用語が一貫して翻訳されます。

```
{{<<Japanese>>, <<English>>, <<Context>>},
 {"展開", "expand", "パラグラフ展開機能"},
 {"翻訳", "translate", "言語変換機能"}}
```

### 図にラベルを付けて本文から参照する

画像セルを選択してパレットの「■ 図メタ」ボタンを押し、ラベル（例: `fig:architecture`）とキャプションを設定します。本文中では `<<fig:architecture>>` と記述すると、エクスポート時に自動的に図番号参照に変換されます。

### Bibliography セルで文献を管理する

```
{{<<Key>>, <<Author>>, <<Year>>, <<Title>>},
 {"wolfram2002", "Wolfram S", "2002", "A New Kind of Science"}}
```

本文中で `<<cite:wolfram2002>>` と記述すると、Markdown エクスポートでは `[wolfram2002]`、LaTeX では `\cite{wolfram2002}` に変換されます。

### 複数セルをまとめて展開する

```mathematica
nb   = EvaluationNotebook[];
idxs = {3, 5, 7};
Scan[DocExpandIdea[nb, #] &, idxs]
```

展開済みのセルも更新対象となります。

### フォールバックモデルを許可して展開する

```mathematica
DocExpandIdea[EvaluationNotebook[], 5, Fallback -> True]
```

### ノートブックを各形式にエクスポートする（試験的）

```mathematica
(* Markdown エクスポート *)
DocExportMarkdown[EvaluationNotebook[]]

(* LaTeX エクスポート *)
DocExportLaTeX[EvaluationNotebook[]]

(* 数式を LLM で高再現度変換してエクスポート *)
DocExportLaTeX[EvaluationNotebook[], "MathFormat" -> True]

(* MS-Word エクスポート（Pandoc が必要） *)
DocExportWord[EvaluationNotebook[]]

(* テンプレートを指定して MS-Word エクスポート *)
DocExportWord[EvaluationNotebook[], "ReferenceDoc" -> "template.docx"]
```

### 任意セルをエクスポート対象外に設定する

セルを選択してパレットの「除外切替」ボタンを押すと、そのセルがエクスポートから除外されます。もう一度押すと解除されます。

---

## 免責事項

本ソフトウェアは "as is"（現状有姿）で提供されており、明示・黙示を問わずいかなる保証もありません。
本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。
今後の動作保証のための更新が行われるとは限りません。
本ソフトウェアとドキュメントはほぼすべてが生成AIによって生成されたものです。
Windows 11上での実行を想定しており、MacOS, LinuxのMathematicaでの動作検証は一切していません(生成AIの処理で対応可能と想定されます)。

---

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.