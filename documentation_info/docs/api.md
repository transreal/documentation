# Documentation` — API リファレンス

パッケージ: `Documentation`
依存: [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode)
ロード: `Needs["Documentation`"]`

セル単位のアイデア→パラグラフ展開・翻訳・同期を行うドキュメント執筆支援パッケージ。LLM呼び出しはNBAccess`NBCellTransformWithLLM経由。パレットから操作するか、直接API呼び出しで使う。

## 定数・変数

### $DocTranslationLanguage
型: String, 初期値: `"English"`（`$Language`が非英語の場合）または`"Japanese"`（英語の場合）
翻訳先言語名。ユーザーが任意の言語名に変更可能。例: `$DocTranslationLanguage = "French"`

## コア関数

### DocExpandIdea[nb, cellIdx, opts]
指定セルのテキストをLLMで文章品質のパラグラフに展開する。非同期実行（カーネルをブロックしない）。
- mode未設定（初回）: アイデア→パラグラフに展開
- mode="idea"（プロンプト表示中）: 保存済みパラグラフがあれば修正アイデア+旧パラグラフを渡して再展開、なければ初回展開
- mode="paragraph"（パラグラフ表示中）: 展開禁止、MessageDialogを表示して`$Failed`を返す
完了後、元テキストをTaggingRulesに保存しmode="paragraph"に設定、セルに緑枠線を付与。
→ `Null`（非同期）または`$Failed`
Options: `Fallback -> False`（True: 課金APIへのフォールバックを許可）
例: `DocExpandIdea[EvaluationNotebook[], 3]`
例（再展開）: `DocExpandIdea[EvaluationNotebook[], 3, Fallback -> True]`

### DocToggleView[nb, cellIdx] → String | Null | $Failed
セルのアイデア・パラグラフ・翻訳の表示を循環切替する。現在表示中の内容を保存してから切り替える。
切替ロジック:
- mode="translated"かつ翻訳表示中 → 元テキストに戻す（水色枠）
- mode="translated"かつ元テキスト表示中 → 翻訳を表示（青枠）
- 翻訳表示中（showTranslation=True） → アイデアに戻す
- mode="paragraph"かつ翻訳あり → 翻訳表示へ
- mode="paragraph"かつ翻訳なし → アイデアへ
- mode="idea" → パラグラフへ
トグル可能なコンテンツがない場合（展開前）はMessageDialogを表示して`$Failed`を返す。

### DocTranslate[nb, cellIdx, opts]
セルの現在表示テキストをLLMで翻訳する。非同期実行。翻訳結果はTaggingRulesに保持し、切替可能。
- mode="idea"（プロンプトモード）では翻訳不可（MessageDialog）
- 翻訳表示中（showTranslation=True）では翻訳不可（MessageDialog）
- 保存済み翻訳がありソースが一致する場合 → LLM不要で即表示
- mode="paragraph" → `iDocTranslationTarget[]`（`$DocTranslationLanguage`）の言語に翻訳
- mode未設定の普通のセル → テキスト言語を自動検出して翻訳方向を決定
再翻訳時はユーザーが修正した既存翻訳を踏襲して更新。
→ `Null`（非同期）または`$Failed`
Options: `Fallback -> False`（True: 課金APIへのフォールバックを許可）

### DocSync[nb, cellIdx, opts]
現在表示中のテキストを基準として、他のコンポーネントをLLMで更新する。セル表示は変更しない。
- mode="idea"（プロンプト表示中）: プロンプトから→パラグラフ再生成。翻訳があれば連鎖で再翻訳
- mode="paragraph"（パラグラフ表示中）: パラグラフから→翻訳を再生成（翻訳が存在しない場合は`$Failed`）
- showTranslation=True（翻訳表示中）: 翻訳の編集をパラグラフに逆反映
- それ以外: MessageDialogを表示
非同期実行。WindowStatusAreaで進捗表示。TaggingRulesにsyncTagを付与しインデックスずれに対応。
→ `Null`（非同期）または`$Failed`
Options: `Fallback -> False`（True: 課金APIへのフォールバックを許可）
例: `DocSync[EvaluationNotebook[], 5]`

## パレット

### ShowDocPalette[] → NotebookObject
ドキュメント作成用フローティングパレットを表示する。既存パレットがあれば閉じてから再作成。
パレット機能:
- **展開**: 選択セルのアイデアを展開（複数選択時は非同期チェーンで逐次展開）
- **切替**: 選択セルのアイデア/パラグラフ/翻訳を切替
- **翻訳**: 選択セルを翻訳（複数選択時は逐次翻訳）
- **同期**: 選択セルの各コンポーネントを同期
- **全プロンプト**: ノートブック全体をプロンプト表示に切替
- **全パラグラフ**: ノートブック全体をパラグラフ表示に切替
- **全翻訳**: ノートブック全体を翻訳表示に切替
- モデル/エフォート/課金API設定（ClaudeCode`と共有）
パッケージロード時に自動表示される。メニュー「パレット」→「Documentation」でも起動可能。

## セルモードとTaggingRules構造

セルのモードは`TaggingRules`の`{"documentation", "mode"}`に格納。

| mode値 | 表示内容 | 枠線色 |
|--------|----------|--------|
| 未設定 | 通常セル | なし |
| `"idea"` | プロンプト（アイデア） | 琥珀色 |
| `"paragraph"` | 展開パラグラフ | 緑 |
| `"translated"` | 翻訳付き普通セル | 水色（元）/青（翻訳） |
| `"paragraph"` + showTrans=True | 翻訳表示 | 青 |

TaggingRulesキー（すべてルート`"documentation"`以下）:
- `"mode"`: セルの現在モード
- `"alternate"`: トグル先テキスト（ideaモード時はパラグラフ、paragraphモード時はアイデア）
- `"translation"`: 保存済み翻訳テキスト
- `"translationSrc"`: 翻訳元テキスト（キャッシュ用）
- `"showTranslation"`: 翻訳表示中フラグ（Boolean）
- `"syncTag"`: Sync操作中の一時タグ（インデックスずれ対応）