# documentation

Mathematica ノートブック上でアイデアメモから文章品質のパラグラフを生成するドキュメント作成支援パッケージです。Markdown・LaTeX への（試験的）エクスポートおよびエクスポート対象外の Note スタイルセル挿入にも対応しています。

## 設計思想と実装の概要

### 設計思想: アウトラインプロセッサとしての Mathematica ノートブック

本パッケージは、Mathematica ノートブックを「アウトラインプロセッサ」として拡張することを目的として設計されています。従来、ノートブックは計算結果や数式を記録する場として使われてきましたが、`documentation` パッケージはノートブックを文章執筆の場として再定義します。

執筆の現場では、まず断片的なアイデアや箇条書きのメモを書き、それを推敲して文章に仕上げるという二段階のプロセスが一般的です。本パッケージはこの「アイデア → パラグラフ」という変換フローを LLM によって自動化し、さらにパラグラフと翻訳の双方向同期まで含めた一貫したワークフローを提供します。

### アーキテクチャの核心: 責務分離

パッケージ設計の最も重要な原則は **責務の明確な分離** です。

- **セル内容へのアクセスは NBAccess 経由に限定する**: セルのテキスト読み書き、TaggingRules の操作、セルオプションの変更はすべて [NBAccess](https://github.com/transreal/NBAccess) の公開 API を通じて行います。これにより、機密セルの背景色や CellDingbat など、NBAccess が管理するビジュアル要素を `documentation` パッケージが誤って上書きするリスクを排除しています。視覚スタイルとして `documentation` が制御するのは左側の枠線色のみです。

- **LLM 呼び出しは NBCellTransformWithLLM 経由に限定する**: すべての LLM 呼び出しは `NBAccess\`NBCellTransformWithLLM` または `NBAccess\`$NBLLMQueryFunc` 経由で行います。プライバシーレベルに応じた LLM の自動選択（無課金モデルと課金 API のルーティング）は NBAccess が担当し、`documentation` はプロンプト構築とコールバック処理に専念します。

- **パレット UI のメタデータ解決のみを内部で行う**: `documentation` が直接担当するのは、パレットから操作対象のノートブックとセルインデックスを特定するロジックのみです。

### セル状態管理: TaggingRules による非破壊的なデータ保持

本パッケージの重要な設計上の決断は、アイデアとパラグラフを「表示の切替」によって管理することです。アイデアテキストを書き換えてパラグラフを生成するのではなく、**現在表示中でない内容を TaggingRules に格納し、切替時に入れ替える**という方式を採用しています。

各セルの状態は `TaggingRules` の `{"documentation", "mode"}` に格納され、以下の 4 つのモードを遷移します。

| mode 値 | 表示内容 | 枠線色 |
|---------|----------|--------|
| 未設定 | 通常セル | なし |
| `"idea"` | プロンプト（アイデア） | 琥珀色 |
| `"paragraph"` | 展開パラグラフ | 緑 |
| `"translated"` | 翻訳付き普通セル | 水色（元）/ 青（翻訳） |

翻訳テキストも同様に TaggingRules に保持されるため、一度翻訳したセルは LLM を再呼び出しすることなく瞬時に切替表示できます。ソーステキストが変わった場合のみ再翻訳が走る仕組みです。

### 非同期実行と完了コールバックチェーン

LLM の呼び出しはすべて非同期で実行され、カーネルをブロックしません。複数セルの一括展開・翻訳時は、完了コールバック内で `RunScheduledTask` を使って次のセルの処理を連鎖させることで、逐次処理を実現しています。また、LLM ジョブの実行中にセルが挿入されてインデックスがずれることを想定し、各セルに一意の `syncTag` を付与して完了時に再検索する仕組みを実装しています。

### 翻訳の双方向同期

`DocSync` 関数は現在表示中のテキストを「基準」として、他のコンポーネントを更新します。翻訳表示中に翻訳を編集して同期すると、その変更が元のパラグラフに逆反映されます（逆同期）。この際、出力言語が翻訳元の言語に切り替わらないよう、プロンプトに `$Language` ベースの出力言語を明示的に指定するという細かな配慮がなされています。

### パレット設定の共有

モデル選択・エフォートレベル・課金 API の許可設定は、[claudecode](https://github.com/transreal/claudecode) パッケージのパレット設定機能（`ClaudeCode\`GetPaletteModel` 等）と共有されます。ノートブックを切り替えるたびに設定が自動リロードされ、ノートブックごとに異なる設定を持つことができます。

---

## 詳細説明

### 動作環境

| 項目 | バージョン / 条件 |
|------|-----------------|
| Mathematica | 13.0 以上 |
| OS | Windows 11（64-bit） |
| 依存パッケージ | [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode) |
| 外部サービス | Anthropic Claude API（LLM 機能に必要） |

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

#### 4. パッケージの読み込み

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

(* 6. パレットを手動で再表示する（閉じてしまった場合） *)
ShowDocPalette[]
```

主要な設定変数:

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `$DocTranslationLanguage` | `"English"` または `"Japanese"` | 翻訳先言語名 |

### 主な機能

#### DocExpandIdea[nb, cellIdx]
選択したセルのアイデアテキストを LLM で文章品質のパラグラフに展開します。初回は「アイデア → パラグラフ」の生成、2 回目以降はアイデアを修正した場合に既存パラグラフの文体を踏襲して再展開します。パラグラフ表示中のセルには展開不可（先に「切替」でアイデアモードに戻す必要があります）。`Fallback -> True` オプションで課金 API へのフォールバックを許可できます。

#### DocToggleView[nb, cellIdx]
セルのアイデア・パラグラフ・翻訳の表示を循環切替します。現在表示中の内容（ユーザーが編集した場合も含む）を TaggingRules に保存してから切り替えます。翻訳が存在するパラグラフモードのセルでは「パラグラフ → 翻訳 → アイデア」の順で循環します。

#### DocTranslate[nb, cellIdx]
セルの現在表示テキストを `$DocTranslationLanguage` で指定した言語に翻訳します。翻訳結果は TaggingRules に保持され、ソーステキストが変わっていない場合は LLM を再呼び出しせずに即時表示します。再翻訳時はユーザーが修正した既存翻訳の文体を踏襲して更新します。

#### DocSync[nb, cellIdx]
現在表示中のテキストを基準として、他のコンポーネントを LLM で更新します。
- アイデア表示中 → パラグラフを再生成（翻訳があれば連鎖で再翻訳）
- パラグラフ表示中 → 翻訳を再生成
- 翻訳表示中 → 翻訳の編集内容をパラグラフに逆反映

#### DocInsertNote[nb]
現在のカーソル位置に **Note スタイル**のセルを挿入します。Note セルはノートブック上には通常のテキストとして表示されますが、**Markdown・LaTeX エクスポート時に本文から除外**されます。執筆中のメモ・TODO・コメントなど、最終出力に残したくない注釈を本文と混在させて置いておくのに適しています。ノートブックに `"Note"` スタイルが既に定義されている場合はそれを使用し、なければパッケージ組み込みのカスタムスタイルを適用します。

#### DocExportMarkdown[nb] *(試験的)*
ノートブックを Markdown 形式でエクスポートします。出力先は `NotebookDirectory[]/<ノートブック名>_md/` です。Note スタイルのセルは出力から除外されます。ラスター画像は PNG、ベクター画像・計算結果は PDF で保存されます。Input セルはコードブロック（` ```mathematica ``` `）、数式は TeX 形式に変換されます。

#### DocExportLaTeX[nb] *(試験的)*
ノートブックを LaTeX 形式でエクスポートします。出力先は `NotebookDirectory[]/<ノートブック名>_LaTeX/` です。Note スタイルのセルは出力から除外されます。画像処理・数式変換の方針は Markdown エクスポートと同じです。Input セルは `lstlisting` 環境として出力されます。

#### ShowDocPalette[]
ドキュメント作成用フローティングパレットを表示します。パッケージロード時に自動表示されますが、閉じた場合はこの関数で再表示できます。メニュー「パレット」→「Documentation」からも起動できます。

**パレットボタン一覧:**

| ボタン | 機能 |
|--------|------|
| ▶ 展開 | 選択セルのアイデアをパラグラフに展開（複数選択時は逐次処理） |
| ↔ 切替 | 選択セルのアイデア / パラグラフ / 翻訳を循環切替 |
| » 翻訳 | 選択セルを翻訳（複数選択時は逐次処理） |
| ⇌ 同期 | 選択セルの各コンポーネントを同期 |
| ■ メモ | カーソル位置に Note スタイルセルを挿入（エクスポート対象外） |
| … 全プロンプト | ノートブック全体をアイデア表示に一括切替 |
| ¶ 全パラグラフ | ノートブック全体をパラグラフ表示に一括切替 |
| Â 全翻訳 | ノートブック全体を翻訳表示に一括切替 |
| → Markdown | ノートブックを Markdown 形式でエクスポート（試験的） |
| → LaTeX | ノートブックを LaTeX 形式でエクスポート（試験的） |

#### $DocTranslationLanguage
翻訳先言語名を指定するグローバル変数です。デフォルトは `$Language` が英語以外なら `"English"`、英語なら `"Japanese"` です。任意の言語名（`"French"`, `"German"`, `"Spanish"` 等）を設定できます。

### ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| `api.md` | 全公開関数・変数のリファレンス、セルモードと TaggingRules 構造、エクスポートセルスタイルマッピングの詳細 |
| `user_manual.md` | ユーザーマニュアル、パレット操作ガイド、各関数の引数説明、典型的なワークフロー |
| `example.md` | コード例集（パレット起動、展開、切替、翻訳設定、複数セル操作） |
| `setup.md` | インストール手順、動作要件、トラブルシューティング |

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

### パラグラフをアイデア表示に戻す（トグル）

```mathematica
DocToggleView[EvaluationNotebook[], 2]
```

### フランス語への翻訳を設定してから翻訳する

```mathematica
$DocTranslationLanguage = "French";
DocTranslate[EvaluationNotebook[], 3]
```

### 複数セルをまとめて展開する

```mathematica
nb   = EvaluationNotebook[];
idxs = {3, 5, 7};
Scan[DocExpandIdea[nb, #] &, idxs]
```

### 翻訳を編集してパラグラフに逆反映する

```mathematica
(* 翻訳表示中に同期すると、翻訳の編集内容がパラグラフに反映される *)
DocSync[EvaluationNotebook[], 4]
```

### 課金 API を許可して展開する

```mathematica
DocExpandIdea[EvaluationNotebook[], 5, Fallback -> True]
```

### Note セルを挿入する

```mathematica
(* カーソル位置にエクスポート対象外のメモセルを挿入する *)
DocInsertNote[EvaluationNotebook[]]
```

### ノートブックを Markdown にエクスポートする（試験的）

```mathematica
(* Note セルを除いた本文を Markdown として出力する *)
DocExportMarkdown[EvaluationNotebook[]]
```

### ノートブックを LaTeX にエクスポートする（試験的）

```mathematica
(* Note セルを除いた本文を LaTeX として出力する *)
DocExportLaTeX[EvaluationNotebook[]]
```

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