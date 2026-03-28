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

---

## API キーの設定

`documentation` パッケージの LLM 機能（アイデア展開・翻訳・同期）は  
`NBAccess` および `claudecode` 経由で Anthropic Claude API を呼び出します。

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

---

## よくあるトラブル

| 症状 | 対処法 |
|------|--------|
| `Needs::nocntxt` エラー | `$Path` に `$packageDirectory` が含まれているか確認する |
| `NBAccess` が見つからない | NBAccess を先にロードまたは `$Path` を確認する |
| LLM が応答しない | `claudecode` の API キー設定を確認する |
| 文字化けが発生する | `Block[{$CharacterEncoding = "UTF-8"}, ...]` でロードしているか確認する |
| `DocExportWord` が失敗する | Pandoc がインストールされているか確認する（`pandoc --version`） |

---

## 関連リンク

- documentation リポジトリ: [https://github.com/transreal/documentation](https://github.com/transreal/documentation)
- NBAccess リポジトリ: [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)
- claudecode リポジトリ: [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)